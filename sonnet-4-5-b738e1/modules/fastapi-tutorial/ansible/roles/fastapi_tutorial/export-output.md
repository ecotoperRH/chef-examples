## MIGRATION FAILED for fastapi_tutorial

**Failure Reason:** Stall detected after 2 attempt(s): errors unchanged between attempts, aborting.
Errors remain:
<apme_check_results total="5" errors="0" warnings="0">
  <file path="ansible/roles/fastapi_tutorial/molecule/default/converge.yml">
    <violation line="0" rule="R401" severity="info">List all inbound sources</violation>
  </file>
  <file path="ansible/roles/fastapi_tutorial/tasks/main.yml">
    <violation line="27" rule="R106" severity="medium">An inbound transfer with parameterized source found</violation>
    <violation line="45" rule="R101" severity="medium">A parameterized command execution found</violation>
    <violation line="56" rule="R101" severity="medium">A parameterized command execution found</violation>
    <violation line="67" rule="R101" severity="medium">A parameterized command execution found</violation>
  </file>
</apme_check_results>

### Migration Summary

- **Total items:** 16
- **Completed:** 16
- **Pending:** 0
- **Missing:** 0
- **Errors:** 0
- **Write attempts:** 1
- **Validation attempts:** 2

### Partial Validation Report

Validation incomplete after 2 attempts:
<apme_check_results total="5" errors="0" warnings="0">
  <file path="ansible/roles/fastapi_tutorial/molecule/default/converge.yml">
    <violation line="0" rule="R401" severity="info">List all inbound sources</violation>
  </file>
  <file path="ansible/roles/fastapi_tutorial/tasks/main.yml">
    <violation line="27" rule="R106" severity="medium">An inbound transfer with parameterized source found</violation>
    <violation line="45" rule="R101" severity="medium">A parameterized command execution found</violation>
    <violation line="56" rule="R101" severity="medium">A parameterized command execution found</violation>
    <violation line="67" rule="R101" severity="medium">A parameterized command execution found</violation>
  </file>
</apme_check_results>

### Review Report

Both files look correct. Here is the complete review summary:

---

## Review Summary

### Findings

| # | Category | Severity | File : Task | Description | Status |
|---|----------|----------|-------------|-------------|--------|
| 1 | **Ordering** | High | `tasks/main.yml` : `Enable and start PostgreSQL service` | The PostgreSQL service start task was placed **after** `Install Python dependencies from requirements.txt`. PostgreSQL must be running before any DB provisioning task executes. Moving it immediately after package install is the correct, safe position. | **Fixed** |
| 2 | **Idempotency** | High | `tasks/main.yml` : `Create PostgreSQL user / database / grant` | All three PostgreSQL shell tasks used `changed_when: false`, meaning they always reported **ok** even on first run when they actually created the user, database, and granted privileges. This breaks change tracking and masks real state transitions. Fixed by rewriting each command to first check for existence (via `pg_roles`/`pg_database` queries) and only execute the DDL if needed, then using `changed_when` tied to the DDL output string (`CREATE ROLE`, `CREATE DATABASE`, `GRANT`). | **Fixed** |
| 3 | **Invalid argument_specs default** | Medium | `meta/argument_specs.yml` : `fastapi_tutorial_db_owner` | The `default:` value was `"{{ db_username }}"` — a Jinja2 expression. Argument specs are evaluated statically by Ansible's role argument validation before any variable is resolved; a Jinja2 expression here causes a type-check failure at runtime. Fixed by removing the `default:` key entirely and moving the explanation into the `description:` field. | **Fixed** |

### Changes Made

- **`ansible/roles/fastapi_tutorial/tasks/main.yml`**
  - Moved `Enable and start PostgreSQL service` from position 7 (after pip install) to position 3 (immediately after package install) — ensures PostgreSQL is running for the entire remainder of the play.
  - Replaced `changed_when: false` on all three PostgreSQL shell tasks with existence-check logic (`SELECT 1 FROM pg_roles / pg_database`) so the DDL only runs when the object is absent, and `changed_when` is tied to the DDL confirmation string in stdout.

- **`ansible/roles/fastapi_tutorial/meta/argument_specs.yml`**
  - Removed the invalid `default: "{{ db_username }}"` Jinja2 expression from the `fastapi_tutorial_db_owner` option. Replaced with a plain-prose `description:` that explains the runtime relationship to `db_username`.

### No Issues Found

- **Missing Prerequisites** — All directories (`/opt/fastapi-tutorial`) are created by an explicit `ansible.builtin.file` task before any task writes into them. The service user is `root`, which always exists.
- **Missing Package Dependencies** — All packages consumed by later tasks (`postgresql`, `python3-venv`, `git`, `libpq-dev`) are declared in `fastapi_tutorial_packages` and installed in the first substantive task.
- **Invalid Module Parameters** — No use of non-existent module parameters (e.g., no `variables:` on `ansible.builtin.template`). All module parameters are valid.
- **Missing Argument Specs** — `meta/argument_specs.yml` exists and covers every variable in `defaults/main.yml` plus all five AAP-injected credential variables.
- **Handlers** — `handlers/main.yml` correctly defines both `Reload systemd daemon` and `Restart fastapi-tutorial service`. Both are notified by the systemd unit template task, and `flush_handlers` is called before the service enable/start task.

### Partial Checklist

## Checklist: fastapi_tutorial

### Templates
- [x] cookbooks/fastapi-tutorial/recipes/default.rb → ansible/roles/fastapi_tutorial/templates/fastapi-tutorial.env.j2 (complete) - Converted inline heredoc from recipe to Jinja2 template. Uses AAP credential variable database_url and role defaults for project name and API version.
- [x] cookbooks/fastapi-tutorial/recipes/default.rb → ansible/roles/fastapi_tutorial/templates/fastapi-tutorial.service.j2 (complete) - Converted inline heredoc from recipe to Jinja2 template. All hardcoded values replaced with role variables. Handler notified on change.

### Recipes → Tasks
- [x] cookbooks/fastapi-tutorial/recipes/default.rb → ansible/roles/fastapi_tutorial/tasks/main.yml (complete) - Converted all Chef resources to Ansible tasks. validate_credentials.yml included first. systemctl daemon-reload is a handler. AAP credential variables used for DB provisioning. pip module used instead of execute for pip install.

### Attributes → Variables
- [x] N/A → ansible/roles/fastapi_tutorial/defaults/main.yml (complete) - Created from hardcoded values in recipe. All credential variables use AAP-injected variables. fastapi_password replaced with db_password from AAP credential type.

### Structure Files
- [x] cookbooks/fastapi-tutorial/metadata.rb → ansible/roles/fastapi_tutorial/meta/main.yml (complete) - meta/main.yml already existed and was marked complete. Pending entry from metadata.rb resolved — existing file retained.
- [x] N/A → ansible/roles/fastapi_tutorial/meta/argument_specs.yml (complete) - Generated from defaults/main.yml. Documents all role variables including AAP-injected credential variables (required: true, no default).
- [x] N/A → ansible/roles/fastapi_tutorial/handlers/main.yml (complete) - Created handlers for systemd daemon-reload and fastapi-tutorial service restart. Notified by systemd unit file template task.
- [x] N/A → ansible/roles/fastapi_tutorial/meta/main.yml (complete)

### Molecule Testing
- [x] N/A → ansible/roles/fastapi_tutorial/molecule/default/molecule.yml (complete) - Created by MoleculeAgent (deterministic scaffold)
- [x] N/A → ansible/roles/fastapi_tutorial/molecule/default/converge.yml (complete) - Includes fastapi_tutorial role via ansible.builtin.include_role. AAP credential variables (db_username, db_password, db_name, db_host, database_url) set as play vars so validate_credentials.yml passes in molecule context.
- [x] N/A → ansible/roles/fastapi_tutorial/molecule/default/verify.yml (complete) - Split into 3 plays: (1) filesystem/venv/config file content checks, (2) service facts and port checks, (3) HTTP endpoint and PostgreSQL database checks. All loops use prefixed loop_var and bracket notation. No registered vars in fail_msg strings.
- [x] N/A → ansible/roles/fastapi_tutorial/molecule/default/create.yml (complete) - Created by MoleculeAgent (deterministic scaffold)
- [x] N/A → ansible/roles/fastapi_tutorial/molecule/default/destroy.yml (complete) - Created by MoleculeAgent (deterministic scaffold)

### Credentials → AAP Configuration
- [x] N/A → ansible/roles/fastapi_tutorial/aap-configuration/controller_credential_types.yml (complete)
- [x] N/A → ansible/roles/fastapi_tutorial/aap-configuration/controller_credentials.yml (complete)
- [x] N/A → ansible/roles/fastapi_tutorial/tasks/validate_credentials.yml (complete)


### Telemetry

```
Phase: migrate
Duration: 0.00s

Agent Metrics:
  AAP Collection Discovery: 25.00s
    Tokens: 53293 in, 1100 out
    Tools: aap_get_collection_detail: 3, aap_list_collections: 1, aap_search_collections: 5
    collections_found: 0
  Credential Extractor: 9.93s
    Tokens: 12106 in, 615 out
    credentials_found: 1
  Export Planner: 66.25s
    Tokens: 268238 in, 3419 out
    Tools: add_checklist_task: 12, list_checklist_tasks: 2, list_directory: 2, read_file: 1
  Ansible Role Writer: 167.92s
    Tokens: 643479 in, 7762 out
    Tools: ansible_lint: 3, ansible_write: 4, file_search: 3, list_checklist_tasks: 2, list_directory: 8, read_file: 4, update_checklist_task: 7, write_file: 2
    attempts: 1
    complete: True
    files_created: 11
    files_total: 16
  Molecule Test Generator: 69.17s
    Tokens: 153187 in, 4177 out
    Tools: ansible_lint: 3, list_checklist_tasks: 1, list_directory: 1, read_file: 6, update_checklist_task: 2, write_file: 2
    attempts: 1
    complete: True
  ReviewAgent: 121.77s
    Tokens: 129343 in, 8388 out
    Tools: add_checklist_task: 2, ansible_write: 2, list_directory: 8, read_file: 11, update_checklist_task: 2
  Ansible Validator: 265.45s
    Tokens: 514270 in, 16119 out
    Tools: ansible_lint: 3, ansible_role_check: 8, ansible_rule_doc: 6, ansible_write: 8, read_file: 14
    violations: 5
    errors: 0
    warnings: 0
    attempts: 2
    complete: False
    has_errors: True
```