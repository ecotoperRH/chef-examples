# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile configuration for a small multi-service development environment: Nginx serves three TLS-enabled static sites, Redis and Memcached provide cache services, and a FastAPI tutorial application runs with a local PostgreSQL database. The defined Chef run list contains three local cookbooks, supplemented by Supermarket cookbooks. Migration is moderate in scope (three local cookbooks) but has meaningful operational risk because of OS inconsistencies, firewall/SSH hardening, self-signed TLS, third-party application installation from a floating Git branch, and plaintext credentials. A two-person team can normally implement, test, and document the Ansible replacement in approximately 2–3 weeks, subject to target-OS and production-certificate decisions.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and configures Memcached and a password-protected Redis instance on port 6379. It creates the Redis log directory, invokes the `redisio` cookbook and enable recipe, and applies a Ruby post-processing workaround to remove selected replication and buffer directives from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached via the `memcached` cookbook; Redis via `redisio`; Redis authentication; Redis service enablement; direct configuration-file workaround.

- **fastapi-tutorial**:
  - Description: Deploys the FastAPI tutorial application from GitHub into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs its Python requirements, installs and starts PostgreSQL, provisions a PostgreSQL role and database, writes an application environment file, and runs Uvicorn as a systemd service.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/venv and Git installation; Git checkout of `dibanez/fastapi_tutorial` branch `main`; local PostgreSQL database and grants; `.env` generation; root-run systemd Uvicorn service on port 8000.

- **nginx-multisite**:
  - Description: Configures Nginx as a multi-site HTTPS web server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`; deploys their static content; generates self-signed certificates; and applies host/network hardening.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration and virtual hosts; static content deployment; self-signed RSA-2048 certificates; Fail2ban; UFW default-deny firewall with SSH/HTTP/HTTPS allowances; sysctl hardening; SSH root-login and password-authentication disablement.

**CRITICAL PATH VERIFICATION:** All paths above are present in the supplied repository tree. The inventory intentionally lists only the three local cookbooks; Supermarket cookbooks are dependencies and are addressed below rather than represented as local migration modules.

### Infrastructure Files

- `Berksfile`: Declares local cookbook paths and Supermarket sources/constraints. Replace Berkshelf resolution with version-pinned Ansible collections, roles, and Python package dependencies managed through `requirements.yml` and execution-environment or CI dependency controls.
- `Policyfile.rb`: Defines the authoritative Chef run order: Nginx/security first, then cache, then FastAPI. Preserve the dependency-aware order with a top-level Ansible site playbook.
- `Policyfile.lock.json`: Locks the resolved external cookbook versions, including `nginx` 12.3.1, `memcached` 6.1.0, and `redisio` 7.2.4. Use it as the current-state dependency baseline, not as a target dependency mechanism.
- `solo.rb`: Chef Solo cache, cookbook-path, and logging configuration. It is retired by Ansible; replace execution behavior with an inventory, `ansible.cfg`, CI runner configuration, and a documented bootstrap process.
- `solo.json`: Provides the Chef run list and Nginx/security overrides. Convert its site, TLS-path, firewall, Fail2ban, and SSH settings into typed role defaults plus environment/group variables.
- `Vagrantfile`: Defines a `generic/fedora42` VM, libvirt provider, 2 GB RAM, two vCPUs, private IP `192.168.121.10`, and forwarded ports 80/443 to 8080/8443. Retain it for local Ansible testing or replace the Chef provisioning hook with `ansible_local`/host-side provisioning. Its Fedora declaration must be reconciled before role development.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef from a remote shell script, runs Berkshelf, and invokes Chef Solo. Retire the Chef-specific workflow; replace with Ansible installation/bootstrap only if Vagrant local provisioning remains required.
- `cookbooks/nginx-multisite/attributes/default.rb`: Current default data model for three sites, certificate/key directories, and security feature flags. Convert to role defaults and validate override precedence.
- `cookbooks/nginx-multisite/templates/` and `files/default/`: Nginx, site, Fail2ban, security/sysctl templates and static site pages. Convert templates to Jinja2 and static content to `copy` or role files while preserving intended ownership and modes.

### Target Details

- **Operating System**: The Chef cookbook metadata supports Ubuntu 18.04+ and CentOS 7+, while provisioning uses `apt-get`, Debian/Ubuntu conventions (`ufw`, `www-data`, `/etc/nginx/sites-available`), and service name `ssh`. These implementation details make Ubuntu/Debian the effective target. The Vagrant box is Fedora 42, which conflicts with these assumptions and is not compatible without adaptations such as DNF, firewalld, `nginx` ownership conventions, and potentially different package/service layouts. The target OS/version must be selected explicitly; do not default to RHEL 9 because the repository provides stronger Ubuntu-specific evidence.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; therefore KVM/libvirt is the indicated local VM platform.
- **Cloud Platform**: Not specified. No cloud-provider tooling, metadata endpoint, or cloud resource configuration was identified.

## Migration Approach

Create an Ansible repository with a top-level `site.yml`, an inventory separated by environment, and reusable roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`. Put non-secret site and security settings in `group_vars`/role defaults; place credentials, private keys, and any real certificate material in Ansible Vault or an approved external secrets manager. Implement idempotently with supported modules rather than Chef shell/Ruby workarounds where possible. Use Molecule or Vagrant/libvirt test instances and integration checks for ports, certificates, HTTP virtual hosts, database connectivity, cache authentication, firewall state, and SSH access before cutover.

### Key Dependencies to Address

- **Chef Infra Client/Solo (Chef >= 16)**: Remove from managed-node provisioning. Replace Chef run lists with Ansible playbooks, inventories, roles, handlers, and CI-driven `ansible-playbook` execution.
- **Berkshelf and Chef Supermarket**: Replace cookbook dependency download with an Ansible `collections/requirements.yml` only where community collections are actually selected; prefer built-in modules for packages, files, templates, services, Git, users, and PostgreSQL where adequate.
- **nginx Chef cookbook (~> 12.0; locked 12.3.1)**: The local Nginx recipe mostly manages the package and configuration directly; implement a dedicated Ansible Nginx role using package/service/template modules rather than translating cookbook internals.
- **memcached Chef cookbook (~> 6.0; locked 6.1.0)**: Use OS package management and `ansible.builtin.service`/`systemd` to install, enable, and configure Memcached. Confirm whether a custom Memcached configuration is needed, since none is visible in the local cookbook.
- **redisio Chef cookbook (~> 7.2.4; locked 7.2.4)**: Replace with distribution Redis packages and an Ansible-managed Redis configuration/service, explicitly modeling port 6379, `requirepass`, log directory ownership, and only the intended replication/buffer settings. Eliminate the Chef Ruby file-edit workaround.
- **PostgreSQL packages and `psql` commands**: Use an Ansible PostgreSQL collection/module (for example, `community.postgresql`) with its required controller/target Python driver, or carefully managed native commands if collection use is not approved. Model role, database, ownership, and privileges declaratively.
- **Python application dependencies**: Use `ansible.builtin.pip` with a virtual environment, `ansible.builtin.git` pinned to an immutable commit or reviewed release tag, and a requirements lock strategy. The current application repository and its `main` revision are external, mutable dependencies.
- **OpenSSL, Fail2ban, UFW, and sysctl**: Manage with package, template, firewall, and `ansible.posix.sysctl` modules. For RHEL/Fedora, redesign UFW controls for firewalld and validate package/service names.

### Security Considerations

- **Plaintext Redis credential (`cache`)**: `redis_secure_password_123` is embedded in the cache recipe. Move it to Ansible Vault or an external secrets manager, rotate it during migration, restrict Redis binding/network exposure, and avoid logging it.
- **Plaintext PostgreSQL/application credential (`fastapi-tutorial`)**: The role password `fastapi_password` appears in shell commands and the generated `.env`/database URL. Store it as a vaulted secret, rotate it, generate `.env` with restrictive permissions (normally `0600`), and prevent it from appearing in task output using `no_log` where necessary.
- **Application service privilege (`fastapi-tutorial`)**: Uvicorn is configured as `User=root`, exposing the application and Git-deployed code to unnecessary root privileges. Create a dedicated non-login service account, assign only required ownership, and use systemd hardening options appropriate to the application.
- **TLS certificates (`nginx-multisite`)**: The cookbook generates 365-day self-signed RSA-2048 keys under `/etc/ssl/private` with group `ssl-cert` and mode `0640`. This is acceptable only for development/testing as indicated by the provisioning script. For production, use an approved PKI/ACME workflow, store private-key material outside source control and Vault it if distributed by Ansible, define renewal, and validate Nginx TLS settings/cipher policy.
- **Host firewall and SSH hardening (`nginx-multisite`)**: The source applies UFW default deny and permits only SSH, HTTP, and HTTPS; it disables direct root login and password authentication through `sed`. Translate to idempotent firewall and SSH configuration tasks with validation before restart. Establish break-glass/key-based access and console recovery procedures first to prevent lockout.
- **Fail2ban and sysctl templates (`nginx-multisite`)**: Preserve and review the exact jail and kernel-security policies during conversion. Treat policy changes as security-reviewed changes; validate their compatibility with the chosen OS.
- **External downloads and supply chain**: Chef is installed by piping a downloaded script to Bash, cookbook dependencies are downloaded from Supermarket, and application code is synchronized from public GitHub `main`. The Ansible process should use approved package repositories, TLS verification, pinned versions/commits, dependency scanning, and CI approval gates.
- **Credentials inventory by module**: `cache` has a hardcoded Redis password. `fastapi-tutorial` has a hardcoded PostgreSQL password embedded in both provisioning and `.env`. `nginx-multisite` creates TLS private keys and contains certificate path references but no external certificate credential in the reviewed entrypoints. No Chef encrypted data bags or Chef Vault use was found in the reviewed dependency and primary cookbook files.

### Technical Challenges

- **Conflicting platform evidence**: Fedora 42 is declared in Vagrant, but the provisioner and recipes assume Ubuntu/Debian packages, UFW, `www-data`, Nginx site directories, and `ssh` service naming. Decide whether Ubuntu is the supported baseline or whether roles must support Fedora/RHEL separately. Use explicit OS-family variable files and CI test matrices rather than implicit cross-platform behavior.
- **Configuration drift and Chef workaround in Redis**: The cache cookbook directly edits a generated `/etc/redis/6379.conf` after `redisio` runs to remove five settings. Confirm the desired final Redis configuration, then render it deterministically in Ansible. Do not carry forward file mutation logic without documenting why each directive is absent.
- **Nginx/template fidelity**: The entrypoint composes four recipes, templates global/site/security configuration, creates symlinks, and removes the default site. Convert the rendered configuration semantics carefully, validate with `nginx -t`, and use handlers so reloads occur only after valid changes.
- **Database provisioning idempotency**: Chef hides all `psql` failures through `|| true`, which can conceal invalid ownership, authentication, or grant states. Ansible database tasks must explicitly converge and fail meaningfully, with safe check/retry behavior after PostgreSQL startup.
- **Mutable and unauthenticated application deployment model**: The Git `main` branch can change independently of infrastructure, and pip requirements may not be locked in this repository. Pin an application release/commit and introduce artifact or dependency provenance before production use.
- **Service exposure and reverse-proxy integration ambiguity**: FastAPI listens on all interfaces at port 8000, while Nginx serves static virtual hosts. The reviewed files do not establish an Nginx proxy route to FastAPI. Confirm the intended topology, firewall exposure, and whether Uvicorn should bind only to localhost behind Nginx.
- **Coordination and verification**: Assign platform/security ownership for base OS and access policy, application/database ownership for FastAPI and schema credentials, and web ownership for Nginx/TLS. Maintain a parity matrix mapping Chef outcomes to Ansible role tasks, use peer review for security-sensitive changes, and capture runbooks/rollback procedures before disabling Chef.

### Migration Order

1. **Foundation and `nginx-multisite` design**: Select and baseline the target OS; establish inventories, Vault/secrets handling, CI/linting, and Vagrant/libvirt or equivalent test environment. Migrate Nginx static sites in a non-production environment, including template rendering, handlers, and HTTP/HTTPS validation. Implement SSH/firewall changes only after access recovery is tested.
2. **`cache`**: Replace Memcached and Redis cookbook behavior with native packages/configuration, vaulted Redis password, explicit Redis bind/security policy, and cache service health/authentication tests. Resolve the current Redis configuration workaround rather than perpetuating it.
3. **`fastapi-tutorial`**: Migrate Python/Git/venv deployment, PostgreSQL role/database/provisioning, restricted `.env`, dedicated system account, and systemd service. Pin the application version and verify database and service readiness.
4. **Integrated cutover**: Run the top-level playbook in staging, conduct end-to-end TLS/site/cache/database/application tests, document operations and rollback, then schedule production execution. Retain Chef only as a rollback reference until Ansible convergence and monitoring are accepted.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks in scope; no Puppet, Salt, PowerShell, or other infrastructure-as-code module structures are present in the supplied tree.
- `Policyfile.rb` and `solo.json` represent the intended run list and workload scope; their order is Nginx/security, cache, then FastAPI.
- Ubuntu/Debian is assumed to be the intended runtime OS because the executable provisioning and most resource conventions rely on APT, UFW, `www-data`, and Debian-style Nginx sites directories, despite cookbook metadata also naming CentOS and Vagrant selecting Fedora 42.
- The Vagrant/libvirt VM is a local development/test target, not evidence of a production virtualization or cloud platform.
- The generated self-signed certificates are development-only, as the provisioning script explicitly warns about self-signed certificate warnings. Production certificate source, domain ownership, and renewal method are unspecified.
- The public GitHub FastAPI repository, its dependency file, and its application/database schema are external to the reviewed configuration; application compatibility and package pinning need separate validation.
- No production inventory, host groups, DNS automation, monitoring, logging aggregation, backup/restore configuration, HA requirements, or cloud infrastructure are present in the reviewed repository.
- Redis, PostgreSQL, and TLS credentials found in source are examples or development values until owners confirm otherwise; they must be treated as exposed and rotated before any production migration.
- The exact contents and policy intent of Nginx, Fail2ban, sysctl, and site templates were not exhaustively audited in this high-level survey; template-rendering and security-policy parity require validation during implementation.
