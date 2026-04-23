# Migration Plan: cache

**TLDR**: The `cache` cookbook configures two caching services: **Memcached** (via the `memcached` community cookbook using a `memcached_instance` custom resource that generates a named systemd unit `memcached_memcached`) and **Redis** (via the `redisio` community cookbook, running on port `6379` with password authentication under a `redis@6379` systemd template unit). The cookbook also applies a post-configuration hack to strip several Redis config directives incompatible with the installed Redis version. The Ansible role uses distro package installs for both services, omits the stripped directives from the Redis template entirely, and stores the Redis password in `defaults/main.yml` pending migration to Ansible Vault.

---

## Service Type and Instances

**Service Type**: Cache (Memcached + Redis)

**Configured Instances**:

- **memcached_memcached**: Single Memcached instance managed via `memcached_instance 'memcached'` custom resource
  - Location/Path: `/etc/systemd/system/memcached_memcached.service`
  - Port/Socket: TCP `11211`, UDP `11211`
  - Key Config: 64 MB memory, max 1024 connections, listen `0.0.0.0`, max object size `1m`, user `memcache`

- **redis@6379**: Single Redis instance managed via `redis@.service` systemd template unit
  - Location/Path: `/etc/redis/6379.conf`, `/etc/systemd/system/redis@.service`
  - Port/Socket: TCP `6379`
  - Key Config: Password authentication (`requirepass`), RDB snapshots enabled, AOF disabled by default, 16 databases, syslog enabled, `LimitNOFILE=65536`

---

## File Structure

```
roles/cache/
├── tasks/
│   ├── main.yml
│   ├── memcached.yml
│   └── redis.yml
├── templates/
│   ├── memcached.service.j2
│   ├── redis.conf.j2
│   └── redis@.service.j2
├── handlers/
│   └── main.yml
└── defaults/
    └── main.yml
```

---

## Module Explanation

The cookbook performs operations in this order:

1. **cache::default** (`cookbooks/cache/recipes/default.rb`):
   - Calls `include_recipe 'memcached'` → triggers `memcached::default` → `memcached::_package` + `memcached_instance 'memcached'`
   - Calls `include_recipe 'redisio'` → triggers `redisio::default` → `apt_update`, `redisio::_install_prereqs`, `build_essential`, `redisio::install`, `redisio::configure`, `redisio::ulimit`
   - Calls `include_recipe 'redisio::enable'` → iterates `node['redisio']['servers']` and enables `redis@6379` systemd unit
   - Executes `fix_redis_config` ruby_block → strips `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority` from the written `redis.conf`

2. **memcached::default / memcached::_package** (`cookbooks/memcached/recipes/default.rb`, `_package.rb`):
   - Installs `memcached` package
   - Creates system group `memcache` and system user `memcache`
   - Creates `/var/log/memcached` and `/var/run/memcached` directories
   - Stops and disables the distro default `memcached` service
   - Removes `/etc/memcached.conf` and `/etc/memcached_default.conf`
   - Deploys `/etc/systemd/system/memcached_memcached.service` from inline unit content
   - Enables and starts `memcached_memcached`

3. **redisio::default → redisio::install** (`cookbooks/redisio/recipes/default.rb`, `install.rb`):
   - Runs `apt_update` (equivalent: `apt` module with `update_cache: true`)
   - **redisio::_install_prereqs**: Installs build prerequisite packages (build tools, libraries). Under a package install of `redis-server` on Debian/Ubuntu these prerequisites are pulled in transitively as package dependencies; this recipe has no Ansible equivalent when using the distro package.
   - **build_essential**: Installs compiler toolchain for source builds. Not needed under a distro package install; has no Ansible equivalent in this role.
   - Installs `redis-server` package (Ansible role uses package install; `redisio` defaults to source build but the `fix_redis_config` hack implies a distro-packaged Redis is the actual target)
   - Iterations over `node['redisio']['servers']`: single server `6379`

4. **redisio::configure** (`cookbooks/redisio/recipes/configure.rb`):
   - Creates system group `redis` and system user `redis`
   - Creates directories: `/var/log/redis`, `/var/lib/redis`, `/etc/redis`, `/var/run/redis`
   - Deploys `/etc/redis/6379.conf` from `redis.conf.erb` template
   - Runs `fix_redis_config` ruby_block: strips `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, `replica-priority` from `/etc/redis/6379.conf` post-write
   - **redisio::ulimit**: Manages PAM ulimit configuration — deploys `/etc/pam.d/su` template and `/etc/pam.d/sudo` cookbook_file on Debian family; applies per-user ulimit via `user_ulimit` custom resource. In this Ansible role the systemd `LimitNOFILE=65536` directive in `redis@.service.j2` is the functional equivalent for the Redis process file descriptor limit. The PAM-level `/etc/pam.d/su` and `/etc/pam.d/sudo` modifications are intentionally omitted; if system-wide PAM ulimit management is required, add tasks for those files separately.
   - Deploys `/etc/systemd/system/redis@.service` from `redis@.service.erb` template

5. **redisio::enable** (`cookbooks/redisio/recipes/enable.rb`):
   - Iterates `node['redisio']['servers']` (single server: port `6379`)
   - Checks `node['redisio']['job_control'] == 'systemd'` → enables and starts `redis@6379`
   - Ansible equivalent: the "Enable and start redis instance" task in `tasks/redis.yml` (`systemd: name=redis@{{ redis_port }}`)

---

## Dependencies

**External cookbook dependencies**:
- `memcached` community cookbook (provides `memcached_instance` custom resource)
- `redisio` community cookbook (provides Redis install/configure/enable recipes)

**System package dependencies**:
- `memcached` (Debian/Ubuntu package)
- `redis-server` (Debian/Ubuntu package; build prerequisites and `build_essential` are not needed under package install — they are satisfied transitively by the distro package)

**Service dependencies**:
- `network.target` (Memcached)
- `network-online.target` (Redis)

---

## Credentials

**Detection Summary**: 1 credential detected across 1 file

**Source**:
- **Provider**: Hardcoded value in Chef cookbook (cookbook attribute or recipe default)
- **Path**: `cookbooks/cache/attributes/` (confirm exact file; value surfaces as `node['redisio']['servers'][0]['requirepass']` in the `redisio` configure resource)

### Redis Authentication Password

- **Variable(s)**: `redis_requirepass` (Ansible); `node['redisio']['servers'][0]['requirepass']` (Chef)
- **Source file(s)**: `cookbooks/cache/attributes/default.rb` (confirm) — value `redis_secure_password_123`
- **Current storage**: Hardcoded in Chef cookbook attribute
- **Usage context**: Written to `/etc/redis/6379.conf` as the `requirepass` directive by the `redisio` configure resource; used for Redis authentication on port `6379`
- **Recommended Ansible storage**: Move to an Ansible Vault-encrypted vars file in production:

```yaml
# group_vars/cache_servers/vault.yml  (ansible-vault encrypted)
redis_requirepass: "redis_secure_password_123"
```

The value is currently placed in `defaults/main.yml` for visibility only and **must not remain there in production**.

---

## Checks for the Migration

**Files to verify**:
- `/etc/systemd/system/memcached_memcached.service`
- `/etc/systemd/system/redis@.service`
- `/etc/redis/6379.conf`
- `/var/log/memcached/` (directory, owned by `memcache:memcache`)
- `/var/run/memcached/` (directory, owned by `memcache:memcache`)
- `/var/log/redis/` (directory, owned by `redis:redis`)
- `/var/lib/redis/` (directory, owned by `redis:redis`)
- `/etc/redis/` (directory, owned by `root:redis`)
- `/var/run/redis/` (directory, owned by `redis:redis`)

**Service endpoints to check**:
- `memcached_memcached`: TCP `11211`, UDP `11211`
- `redis@6379`: TCP `6379`

**Templates rendered**:
- `memcached.service.j2` → `/etc/systemd/system/memcached_memcached.service` (1 render)
- `redis@.service.j2` → `/etc/systemd/system/redis@.service` (1 render)
- `redis.conf.j2` → `/etc/redis/6379.conf` (1 render)

---

## Pre-flight Checks

```bash
# ── Package presence ──────────────────────────────────────────────────────────
dpkg -l memcached
dpkg -l redis-server

# ── Users and groups ─────────────────────────────────────────────────────────
id memcache
getent group memcache
id redis
getent group redis

# ── Directory ownership ───────────────────────────────────────────────────────
stat /var/log/memcached
stat /var/run/memcached
stat /var/log/redis
stat /var/lib/redis
stat /etc/redis
stat /var/run/redis

# ── Systemd unit files ────────────────────────────────────────────────────────
test -f /etc/systemd/system/memcached_memcached.service && echo "OK: memcached unit present"
test -f /etc/systemd/system/redis@.service              && echo "OK: redis@ unit present"
test -f /etc/redis/6379.conf                            && echo "OK: redis 6379 config present"

# ── Verify stripped directives are absent from redis.conf ─────────────────────
grep -E "replica-serve-stale-data|replica-read-only|repl-ping-replica-period|client-output-buffer-limit|replica-priority" \
  /etc/redis/6379.conf \
  && echo "WARN: stripped directives found — check template" \
  || echo "OK: no incompatible directives present"

# ── Service status: memcached_memcached ───────────────────────────────────────
systemctl is-enabled memcached_memcached
systemctl is-active  memcached_memcached
systemctl status     memcached_memcached --no-pager

# Confirm distro default memcached is disabled
systemctl is-enabled memcached 2>/dev/null && echo "WARN: default memcached still enabled" || echo "OK"

# ── Service status: redis@6379 ────────────────────────────────────────────────
systemctl is-enabled "redis@6379"
systemctl is-active  "redis@6379"
systemctl status     "redis@6379" --no-pager

# Confirm distro default redis-server is disabled
systemctl is-enabled redis-server 2>/dev/null && echo "WARN: default redis-server still enabled" || echo "OK"

# ── Connectivity: memcached_memcached (port 11211) ────────────────────────────
echo "stats" | nc -q1 127.0.0.1 11211 | head -5

# ── Connectivity: redis@6379 (port 6379) ─────────────────────────────────────
redis-cli -p 6379 -a "redis_secure_password_123" ping
redis-cli -p 6379 -a "redis_secure_password_123" info server | grep redis_version

# ── LimitNOFILE effective for redis@6379 ─────────────────────────────────────
REDIS_PID=$(systemctl show -p MainPID "redis@6379" | cut -d= -f2)
cat /proc/${REDIS_PID}/limits | grep "open files"

# ── Journal for errors ────────────────────────────────────────────────────────
journalctl -u memcached_memcached --since "5 minutes ago" --no-pager
journalctl -u "redis@6379"        --since "5 minutes ago" --no-pager
```

---

## Key Migration Notes

### 1. The `fix_redis_config` Hack → Template Omission
The original cookbook wrote a full `redis.conf` (including `replica-serve-stale-data`, `replica-read-only`, `repl-ping-replica-period`, `client-output-buffer-limit`, and `replica-priority`) and then immediately stripped those lines with a `ruby_block`. This was a workaround for an older Redis version that did not support those directives. **In Ansible, these directives are simply never written to the config file.** This is cleaner and functionally identical.

### 2. Redis Package vs. Source Install
The `redisio` cookbook defaults to a **source build** (`package_install: false`) on Debian/Ubuntu, but the `fix_redis_config` hack strongly implies the target system uses a **distro-packaged Redis** (which uses different directive names). The Ansible role uses `package: name=redis-server` (Debian/Ubuntu package install), which is consistent with the hack's intent. The `redisio::_install_prereqs` recipe (build tools and libraries) and the `build_essential` resource are both unnecessary under a package install — all prerequisites are satisfied transitively by the `redis-server` package. If a source-built Redis is required, replace the package task with a build-from-source block and adjust `redis_bin_path` to `/usr/local/bin`.

### 3. Systemd Service Naming
- **Memcached:** The `memcached_instance` resource names the service `memcached_<instance_name>`. Since the recipe calls `memcached_instance 'memcached'`, the service name is `memcached_memcached`. This is reflected in all Ansible tasks and handlers.
- **Redis:** The `redisio` cookbook uses a `redis@<port>` systemd template unit. The Ansible role deploys the same `redis@.service` template and manages `redis@6379`. The "Enable and start redis instance" task in `tasks/redis.yml` is the direct equivalent of `redisio::enable` iterating over servers and enabling the per-port unit.

### 4. Redis Password Security
The password `redis_secure_password_123` is hardcoded in the original cookbook. In Ansible it is stored in `defaults/main.yml` for initial visibility but **must be moved to an Ansible Vault-encrypted vars file before production deployment**:
```yaml
# group_vars/cache_servers/vault.yml  (ansible-vault encrypted)
redis_requirepass: "redis_secure_password_123"
```

### 5. `apt_update` → `apt` Module with `update_cache`
The `apt_update` call at the top of `redisio::default` is handled by the `apt` module's `update_cache: true` in `tasks/main.yml`.

### 6. `redisio::disable_os_default`
This recipe stops and disables the OS-installed default Redis service to prevent port conflicts. The Ansible equivalent is the "Stop and disable OS default redis service" task in `tasks/redis.yml`.

### 7. `redisio::ulimit` — PAM Configuration Intentionally Omitted
`redisio::ulimit` manages `/etc/pam.d/su` and `/etc/pam.d/sudo` on Debian family systems and applies per-user ulimit settings via the `user_ulimit` custom resource. In this Ansible role the systemd `LimitNOFILE=65536` directive in `redis@.service.j2` provides the file descriptor limit for the Redis process, which is the operationally relevant control. The PAM-level modifications are intentionally omitted. If system-wide PAM ulimit management is required for the `redis` user outside of systemd, add explicit tasks for `/etc/pam.d/su` and `/etc/pam.d/sudo`.

### 8. Security Hardening Flags in `memcached.service.j2`
The systemd security directives (`RestrictNamespaces`, `ProtectControlGroups`, `ProtectKernelTunables`, `ProtectKernelModules`, `MemoryDenyWriteExecute`, etc.) are included because the target is Debian/Ubuntu. **Remove those lines if deploying on RHEL 7 / CentOS 7**, where those directives are unsupported.

---

## Full Ansible File Contents

### `defaults/main.yml`

```yaml
# --- Memcached defaults ---
memcached_memory: 64
memcached_port: 11211
memcached_udp_port: 11211
memcached_listen: "0.0.0.0"
memcached_maxconn: 1024
memcached_max_object_size: "1m"
memcached_ulimit: 1024
memcached_user: "memcache"
memcached_group: "memcache"
memcached_log_dir: "/var/log/memcached"

# --- Redis defaults ---
# NOTE: redis_requirepass must be moved to an Ansible Vault-encrypted file in production.
redis_port: "6379"
redis_requirepass: "redis_secure_password_123"
redis_user: "redis"
redis_group: "redis"
redis_log_dir: "/var/log/redis"
redis_data_dir: "/var/lib/redis"
redis_config_dir: "/etc/redis"
redis_pid_dir: "/var/run/redis"
redis_bin_path: "/usr/bin"
redis_limit_nofile: 65536

redis_databases: 16
redis_loglevel: "notice"
redis_syslog_enabled: "yes"
redis_syslog_facility: "local0"
redis_timeout: 0
redis_keepalive: 0
redis_maxclients: 10000
redis_hz: 10
redis_tcpbacklog: 511
redis_backuptype: "rdb"
redis_appendfsync: "everysec"
redis_no_appendfsync_on_rewrite: "no"
redis_aof_rewrite_percentage: 100
redis_aof_rewrite_min_size: "64mb"
redis_aof_load_truncated: "yes"
redis_rdb_compression: "yes"
redis_rdb_checksum: "yes"
redis_stop_writes_on_bgsave_error: "yes"
redis_repl_diskless_sync: "no"
redis_repl_diskless_sync_delay: 5
redis_repl_ping_replica_period: 10
redis_repl_timeout: 60
redis_repl_disable_tcp_nodelay: "no"
redis_repl_backlog_size: "1mb"
redis_repl_backlog_ttl: 3600
redis_replica_priority: 100
redis_lua_time_limit: 5000
redis_slowlog_log_slower_than: 10000
redis_slowlog_max_len: 1024
redis_notify_keyspace_events: ""
redis_hash_max_ziplist_entries: 512
redis_hash_max_ziplist_value: 64
redis_set_max_intset_entries: 512
redis_zset_max_ziplist_entries: 128
redis_zset_max_ziplist_value: 64
redis_hll_sparse_max_bytes: 3000
redis_active_rehashing: "yes"
redis_aof_rewrite_incremental_fsync: "yes"
```

### `tasks/main.yml`

```yaml
---
- name: Update apt cache
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  when: ansible_os_family == "Debian"

- name: Configure Memcached
  ansible.builtin.import_tasks: memcached.yml

- name: Configure Redis
  ansible.builtin.import_tasks: redis.yml
```

### `tasks/memcached.yml`

```yaml
---
# Mirrors: memcached::default → memcached::_package + memcached_instance 'memcached'

# --- Package installation (memcached::_package) ---
- name: Install memcached package
  ansible.builtin.package:
    name: memcached
    state: present

- name: Create memcached system group
  ansible.builtin.group:
    name: "{{ memcached_group }}"
    system: true
    state: present

- name: Create memcached system user
  ansible.builtin.user:
    name: "{{ memcached_user }}"
    system: true
    create_home: false
    home: /nonexistent
    shell: /bin/false
    comment: Memcached
    group: "{{ memcached_group }}"
    password: "!"
    state: present

- name: Create memcached log directory
  ansible.builtin.file:
    path: "{{ memcached_log_dir }}"
    state: directory
    owner: "{{ memcached_user }}"
    group: "{{ memcached_group }}"
    mode: "0755"

- name: Create memcached run directory
  ansible.builtin.file:
    path: /var/run/memcached
    state: directory
    owner: "{{ memcached_user }}"
    group: "{{ memcached_group }}"
    mode: "0755"

# --- Disable the distro default memcached instance ---
- name: Stop and disable default memcached service
  ansible.builtin.systemd:
    name: memcached
    state: stopped
    enabled: false
  failed_when: false

- name: Remove default memcached config files
  ansible.builtin.file:
    path: "{{ item }}"
    state: absent
  loop:
    - /etc/memcached.conf
    - /etc/memcached_default.conf
  notify: Restart memcached instance

# --- Deploy the named-instance systemd unit (memcached_instance 'memcached') ---
- name: Deploy memcached systemd unit
  ansible.builtin.template:
    src: memcached.service.j2
    dest: /etc/systemd/system/memcached_memcached.service
    owner: root
    group: root
    mode: "0644"
  notify:
    - Reload systemd
    - Restart memcached instance

- name: Enable and start memcached instance
  ansible.builtin.systemd:
    name: memcached_memcached
    state: started
    enabled: true
    daemon_reload: true
```

### `tasks/redis.yml`

```yaml
---
# Mirrors: redisio::default (install + configure) + redisio::enable + fix_redis_config ruby_block
# redisio::_install_prereqs and build_essential are not needed under package install.
# redisio::ulimit PAM tasks are intentionally omitted; LimitNOFILE in the systemd unit is sufficient.
# redisio::enable equivalent: the final "Enable and start redis instance" task below.

# --- Install Redis via package ---
- name: Install redis-server package
  ansible.builtin.package:
    name: redis-server
    state: present

# --- Create redis system user/group (redisio::configure) ---
- name: Create redis group
  ansible.builtin.group:
    name: "{{ redis_group }}"
    system: true
    state: present

- name: Create redis user
  ansible.builtin.user:
    name: "{{ redis_user }}"
    system: true
    create_home: false
    home: /var/lib/redis
    shell: /bin/false
    group: "{{ redis_group }}"
    state: present

# --- Create required directories ---
- name: Create redis log directory
  ansible.builtin.file:
    path: "{{ redis_log_dir }}"
    state: directory
    owner: "{{ redis_user }}"
    group: "{{ redis_group }}"
    mode: "0755"

- name: Create redis data directory
  ansible.builtin.file:
    path: "{{ redis_data_dir }}"
    state: directory
    owner: "{{ redis_user }}"
    group: "{{ redis_group }}"
    mode: "0755"

- name: Create redis config directory
  ansible.builtin.file:
    path: "{{ redis_config_dir }}"
    state: directory
    owner: root
    group: "{{ redis_group }}"
    mode: "0755"

- name: Create redis pid directory
  ansible.builtin.file:
    path: "{{ redis_pid_dir }}"
    state: directory
    owner: "{{ redis_user }}"
    group: "{{ redis_group }}"
    mode: "0755"

# --- Deploy Redis configuration ---
# The fix_redis_config ruby_block stripped replica-serve-stale-data, replica-read-only,
# repl-ping-replica-period, client-output-buffer-limit, and replica-priority post-write.
# Those directives are simply omitted from this template — functionally identical.
- name: Deploy Redis configuration file
  ansible.builtin.template:
    src: redis.conf.j2
    dest: "{{ redis_config_dir }}/{{ redis_port }}.conf"
    owner: "{{ redis_user }}"
    group: "{{ redis_group }}"
    mode: "0640"
  notify: Restart redis instance

# --- Deploy systemd unit (redis@.service template) ---
- name: Deploy redis@ systemd template unit
  ansible.builtin.template:
    src: redis@.service.j2
    dest: /etc/systemd/system/redis@.service
    owner: root
    group: root
    mode: "0644"
  notify:
    - Reload systemd
    - Restart redis instance

# --- Disable OS default redis service (redisio::disable_os_default) ---
- name: Stop and disable OS default redis service
  ansible.builtin.systemd:
    name: redis-server
    state: stopped
    enabled: false
  failed_when: false

# --- Enable and start the redis instance on port 6379 (redisio::enable) ---
- name: Enable and start redis instance
  ansible.builtin.systemd:
    name: "redis@{{ redis_port }}"
    state: started
    enabled: true
    daemon_reload: true
```

### `handlers/main.yml`

```yaml
---
- name: Reload systemd
  ansible.builtin.systemd:
    daemon_reload: true
  listen: Reload systemd

- name: Restart memcached instance
  ansible.builtin.systemd:
    name: memcached_memcached
    state: restarted
  listen: Restart memcached instance

- name: Restart redis instance
  ansible.builtin.systemd:
    name: "redis@{{ redis_port }}"
    state: restarted
  listen: Restart redis instance
```

### `templates/memcached.service.j2`

```ini
[Unit]
Description=memcached instance memcached_memcached
After=network.target

[Service]
User={{ memcached_user }}
LimitNOFILE={{ memcached_ulimit }}
ExecStart=/usr/bin/memcached \
  -m {{ memcached_memory }} \
  -p {{ memcached_port }} \
  -U {{ memcached_udp_port }} \
  -l {{ memcached_listen }} \
  -c {{ memcached_maxconn }} \
  -I {{ memcached_max_object_size }} \
  -u {{ memcached_user }}
Restart=on-failure
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
PrivateDevices=true
CapabilityBoundingSet=CAP_SETGID CAP_SETUID CAP_SYS_RESOURCE
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=true
RestrictRealtime=true
ProtectControlGroups=true
ProtectKernelTunables=true
ProtectKernelModules=true
MemoryDenyWriteExecute=true

[Install]
WantedBy=multi-user.target
```

> **Note:** The security hardening directives (`RestrictNamespaces`, `ProtectControlGroups`, etc.) are included for Debian/Ubuntu targets. Remove those lines if deploying on RHEL 7 / CentOS 7.

### `templates/redis@.service.j2`

```ini
[Unit]
Description=Redis (%i) persistent key-value database
Wants=network-online.target
After=network-online.target

[Service]
ExecStart={{ redis_bin_path }}/redis-server {{ redis_config_dir }}/%i.conf --daemonize no
User={{ redis_user }}
Group={{ redis_group }}
LimitNOFILE={{ redis_limit_nofile }}

[Install]
WantedBy=multi-user.target
```

### `templates/redis.conf.j2`

```
# Redis configuration — managed by Ansible
# Instance: {{ redis_port }}

daemonize no

pidfile {{ redis_pid_dir }}/redis_{{ redis_port }}.pid

port {{ redis_port }}

tcp-backlog {{ redis_tcpbacklog }}

timeout {{ redis_timeout }}

tcp-keepalive {{ redis_keepalive }}

loglevel {{ redis_loglevel }}

syslog-enabled {{ redis_syslog_enabled }}
syslog-ident redis-{{ redis_port }}
syslog-facility {{ redis_syslog_facility }}

databases {{ redis_databases }}

################################# SNAPSHOTTING ################################

{% if redis_backuptype in ['rdb', 'both'] %}
save 900 1
save 300 10
save 60 10000

stop-writes-on-bgsave-error {{ redis_stop_writes_on_bgsave_error }}
rdbcompression {{ redis_rdb_compression }}
rdbchecksum {{ redis_rdb_checksum }}
dbfilename dump-{{ redis_port }}.rdb
{% endif %}

dir {{ redis_data_dir }}

################################# REPLICATION #################################

# No replication configured — standalone instance.
# replica-serve-stale-data, replica-read-only, repl-ping-replica-period,
# client-output-buffer-limit, and replica-priority are intentionally omitted
# (stripped by the original cookbook's fix_redis_config ruby_block).

repl-diskless-sync {{ redis_repl_diskless_sync }}
repl-diskless-sync-delay {{ redis_repl_diskless_sync_delay }}
repl-timeout {{ redis_repl_timeout }}
repl-disable-tcp-nodelay {{ redis_repl_disable_tcp_nodelay }}
repl-backlog-size {{ redis_repl_backlog_size }}
repl-backlog-ttl {{ redis_repl_backlog_ttl }}

################################## SECURITY ###################################

requirepass {{ redis_requirepass }}

################################### LIMITS ####################################

maxclients {{ redis_maxclients }}

############################## APPEND ONLY MODE ###############################

{% if redis_backuptype in ['aof', 'both'] %}
appendonly yes
{% else