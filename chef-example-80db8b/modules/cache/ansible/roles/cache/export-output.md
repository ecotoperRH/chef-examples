## MIGRATION FAILED for cache

**Failure Reason:** Stall detected after 2 attempt(s): errors unchanged between attempts, aborting.
Errors remain:
<apme_check_results total="1" errors="0" warnings="0">
  <file path="ansible/roles/cache/molecule/default/converge.yml">
    <violation line="0" rule="R401" severity="info">List all inbound sources</violation>
  </file>
</apme_check_results>

### Migration Summary

- **Total items:** 27
- **Completed:** 26
- **Pending:** 0
- **Missing:** 1
- **Errors:** 0
- **Write attempts:** 1
- **Validation attempts:** 2

### Partial Validation Report

Validation incomplete after 2 attempts:
<apme_check_results total="1" errors="0" warnings="0">
  <file path="ansible/roles/cache/molecule/default/converge.yml">
    <violation line="0" rule="R401" severity="info">List all inbound sources</violation>
  </file>
</apme_check_results>

### Review Report

---

## Review Summary

### Findings

| # | Category | Severity | File : Task | Description | Status |
|---|----------|----------|-------------|-------------|--------|
| 1 | **Invalid Module Parameters** | 🔴 High | `redis_configure.yml` : `Deploy Redis systemd unit file` | `vars:` block was indented under `notify:` instead of at task level. Ansible parsed it as a list item inside `notify:` rather than a task-level key, so `redis_bin_path`, `redis_user`, `redis_group`, and `redis_limit_nofile` were never injected into the template. The `redis@.service.j2` template would have rendered with undefined variables, producing a broken systemd unit. | ✅ Fixed |
| 2 | **Ordering / Duplicate Task** | 🟠 Medium | `redis_install.yml` : `Configure PAM su for ulimit support` | The PAM su template task appeared at the **end of `redis_install.yml`** AND in `redis_configure.yml`. The copy in `redis_install.yml` is misplaced — ulimit configuration belongs in the configure phase, not the install phase. On every run it would overwrite `/etc/pam.d/su` a second time unnecessarily, and the task's logical home is `redis_configure.yml` (which already had the correct copy). | ✅ Fixed |
| 3 | **Missing Prerequisites** | 🟡 Low | `memcached.yml` : `Enable and start memcached service` | Role variables `cache_memcached_memory`, `cache_memcached_port`, `cache_memcached_maxconn`, `cache_memcached_ulimit`, etc. are defined in `defaults/main.yml` but are **never applied** to the running service. Memcached starts with OS-package defaults, not the role-defined values. A configuration template for `/etc/memcached.conf` (Debian) or `/etc/sysconfig/memcached` (RHEL) is needed. | ⚠️ Not fixable — source Chef template not available in migration artifacts; flagged for follow-up |

---

### Changes Made

#### `ansible/roles/cache/tasks/redis_configure.yml`
- **Moved `vars:` from inside `notify:` to task level** on the `Deploy Redis systemd unit file` task. In the original file, the `vars:` block was indented at the same depth as the `notify:` list items, making Ansible treat it as a third handler name rather than a task-level key. The four template variables (`redis_bin_path`, `redis_user`, `redis_group`, `redis_limit_nofile`) are now correctly scoped to the task and will be available inside `redis@.service.j2`.
- **Moved the misplaced comment block** (`# PAM ulimit (Debian/Ubuntu only — redisio::ulimit)`) out from inside the `notify:` block to a standalone comment before the PAM su task.

#### `ansible/roles/cache/tasks/redis_install.yml`
- **Removed the duplicate `Configure PAM su for ulimit support` task** from the end of the file. This task was a copy of the one already present in `redis_configure.yml`. Keeping it in `redis_install.yml` caused a redundant double-write of `/etc/pam.d/su` and violated the separation of concerns between install and configure phases.

---

### No Issues Found

- **Missing Prerequisites (users/groups/dirs):** All users (`redis`, `memcache`/`memcached`), groups, and directories are created before they are referenced.
- **Missing Package Dependencies:** Build prerequisites (`tar`, `gcc`, `make`) are installed before the source build. `memcached` package is installed before service management.
- **Idempotency:** All `shell` tasks use either `creates:` guards or `when: not cache_redis_binary_stat.stat.exists` conditions. The breadcrumb pattern for the Redis config is correct. `state: touch` with `modification_time: preserve` + `access_time: preserve` is the correct idempotent touch pattern.
- **Ordering:** Package install → directory creation → config deployment → service start order is correct throughout all task files.
- **Argument Specs:** `meta/argument_specs.yml` exists and covers all variables in `defaults/main.yml` with correct types.

### Partial Checklist

## Checklist: cache

### Templates
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis.conf.erb → ansible/roles/cache/templates/redis.conf.j2 (complete) - Converted ERB to Jinja2. Deprecated directives (replica-serve-stale-data, replica-read-only, repl-ping-replica-period, client-output-buffer-limit, replica-priority) are omitted directly in the template instead of post-processing hack.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/redis@.service.erb → ansible/roles/cache/templates/redis@.service.j2 (complete) - Converted ERB to Jinja2 systemd unit template.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/templates/default/su.erb → ansible/roles/cache/templates/pam_su.j2 (complete) - Static PAM su config - no ERB variables, copied as-is to Jinja2 template.

### Recipes → Tasks
- [x] cookbooks/cache/recipes/default.rb → ansible/roles/cache/tasks/main.yml (complete) - Main entry point: validates credentials, then includes memcached, redis_install, redis_configure tasks.
- [ ] migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/default.rb → ansible/roles/cache/tasks/memcached.yml (missing) - Not fixable without source Chef template: memcached role variables (cache_memcached_memory, cache_memcached_port, cache_memcached_maxconn, etc.) are defined in defaults/main.yml but never applied to the running service. The memcached package on Debian/Ubuntu uses /etc/memcached.conf; on RHEL it uses /etc/sysconfig/memcached. A configuration template would be needed to apply these variables. This is a functional gap but out of scope for this review pass — flagged for follow-up.
- [x] migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/recipes/_package.rb → ansible/roles/cache/tasks/memcached.yml (complete) - Merged _package.rb (package install, user/group, directories) into memcached.yml.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/install.rb → ansible/roles/cache/tasks/redis_install.yml (complete) - Duplicate PAM su task removed. The make install shell task uses args: creates: which is the correct placement for ansible.builtin.shell — no change needed there.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/_install_prereqs.rb → ansible/roles/cache/tasks/redis_install.yml (complete) - Merged into redis_install.yml.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/configure.rb → ansible/roles/cache/tasks/redis_configure.yml (complete) - Fixed: vars: block for 'Deploy Redis systemd unit file' was indented under notify: (making it a child of the notify list), so Ansible could not see it as a task-level key. Moved vars: to correct task-level indentation. Also cleaned up misplaced comment block that was inside the notify: block.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/enable.rb → ansible/roles/cache/tasks/redis_configure.yml (complete) - Merged into redis_configure.yml (start/enable service).
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/disable_os_default.rb → ansible/roles/cache/tasks/redis_install.yml (complete) - Merged into redis_install.yml.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/ulimit.rb → ansible/roles/cache/tasks/redis_configure.yml (complete) - Fixed: Duplicate 'Configure PAM su for ulimit support' task removed from redis_install.yml. The task correctly lives only in redis_configure.yml (ulimit config belongs in configure phase, not install phase).
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/recipes/default.rb → ansible/roles/cache/tasks/redis_install.yml (complete) - Merged into redis_install.yml (apt_update, build_essential, include_recipe calls).

### Attributes → Variables
- [x] migration-dependencies/cookbook_artifacts/memcached-7992788f1a376defb902059063f5295e37d281cb/attributes/default.rb → ansible/roles/cache/defaults/main.yml (complete) - Merged memcached and redisio attributes into single defaults/main.yml. redis_password uses AAP credential variable redis_password.
- [x] migration-dependencies/cookbook_artifacts/redisio-cac70a2ec9102cac4f5391358c8565d244f5d4db/attributes/default.rb → ansible/roles/cache/defaults/main.yml (complete) - Merged into single defaults/main.yml with memcached attributes.

### Structure Files
- [x] cookbooks/cache/metadata.rb → ansible/roles/cache/meta/main.yml (complete) - meta/main.yml already exists and is complete. Skipped to avoid overwriting.
- [x] N/A → ansible/roles/cache/handlers/main.yml (complete) - Created handlers for systemd daemon reload, redis restart, and memcached restart.
- [x] ansible/roles/cache/defaults/main.yml → ansible/roles/cache/meta/argument_specs.yml (complete) - Generated argument_specs.yml documenting all role parameters including redis_password as AAP-injected credential.
- [x] N/A → ansible/roles/cache/meta/main.yml (complete)

### Molecule Testing
- [x] N/A → ansible/roles/cache/molecule/default/molecule.yml (complete) - Created by MoleculeAgent (deterministic scaffold)
- [x] N/A → ansible/roles/cache/molecule/default/converge.yml (complete) - Minimal converge: includes role 'cache' via ansible.builtin.include_role with redis_password molecule test variable set.
- [x] N/A → ansible/roles/cache/molecule/default/verify.yml (complete) - Two-play verify: Play 1 checks Redis binaries, config files, deprecated-directive removal, systemd unit content, service state, port 6379. Play 2 checks Memcached directories, ownership, service state, port 11211, user existence, and OS-default Redis service is stopped.
- [x] N/A → ansible/roles/cache/molecule/default/create.yml (complete) - Created by MoleculeAgent (deterministic scaffold)
- [x] N/A → ansible/roles/cache/molecule/default/destroy.yml (complete) - Created by MoleculeAgent (deterministic scaffold)

### Credentials → AAP Configuration
- [x] N/A → ansible/roles/cache/aap-configuration/controller_credential_types.yml (complete)
- [x] N/A → ansible/roles/cache/aap-configuration/controller_credentials.yml (complete)
- [x] N/A → ansible/roles/cache/tasks/validate_credentials.yml (complete)


### Telemetry

```
Phase: migrate
Duration: 0.00s

Agent Metrics:
  AAP Collection Discovery: 31.55s
    Tokens: 66168 in, 1149 out
    Tools: aap_list_collections: 1, aap_search_collections: 7
    collections_found: 0
  Credential Extractor: 5.23s
    Tokens: 15430 in, 260 out
    credentials_found: 1
  Export Planner: 111.18s
    Tokens: 536037 in, 6224 out
    Tools: add_checklist_task: 23, list_checklist_tasks: 2, list_directory: 9, read_file: 2
  Ansible Role Writer: 347.26s
    Tokens: 2037668 in, 21277 out
    Tools: ansible_lint: 1, ansible_write: 7, list_checklist_tasks: 2, list_directory: 6, read_file: 13, update_checklist_task: 18, write_file: 4
    attempts: 1
    complete: True
    files_created: 22
    files_total: 27
  Molecule Test Generator: 79.41s
    Tokens: 259205 in, 5172 out
    Tools: ansible_lint: 3, list_checklist_tasks: 1, list_directory: 4, read_file: 6, update_checklist_task: 2, write_file: 2
    attempts: 1
    complete: True
  ReviewAgent: 133.97s
    Tokens: 408874 in, 10367 out
    Tools: add_checklist_task: 5, ansible_write: 2, get_checklist_summary: 1, list_directory: 11, read_file: 21, update_checklist_task: 4
  Ansible Validator: 259.64s
    Tokens: 477518 in, 16386 out
    Tools: ansible_lint: 4, ansible_role_check: 5, ansible_rule_doc: 3, ansible_write: 9, read_file: 9
    violations: 1
    errors: 0
    warnings: 0
    attempts: 2
    complete: False
    has_errors: True
```