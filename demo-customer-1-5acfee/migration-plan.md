# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile configuration for a small, single-node development environment. It provisions three local Chef cookbooks in one run list: a hardened Nginx multi-site front end, Memcached and Redis caches, and a FastAPI tutorial application backed by local PostgreSQL. Vagrant/libvirt supplies an intended Fedora 42 VM, although the provisioning bootstrap and several cookbook assumptions are Debian/Ubuntu-specific. The migration is moderate in complexity: the resource count is manageable, but security hardening, TLS, package/service portability, idempotent database provisioning, and removal of exposed credentials require deliberate redesign rather than a literal translation.

A two-person infrastructure/application team can reasonably implement and validate the initial Ansible roles in approximately 2–3 weeks: 2–3 days for discovery and target decisions, 4–6 days for role implementation, 3–5 days for integration/security remediation, and 2–4 days for VM-based test and handover. This estimate excludes production certificate issuance, DNS, PostgreSQL data migration, CI integration, and application changes.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and enables Memcached and Redis. Configures Redis on port 6379 with authentication, creates `/var/log/redis`, and applies an imperative post-processing workaround to remove unsupported or undesired replication-related directives from `/etc/redis/6379.conf`.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached default recipe inclusion; Redis service enablement; Redis password configuration; Redis log-directory ownership; direct Ruby mutation of generated Redis configuration.

- **fastapi-tutorial**:
  - Description: Deploys the FastAPI tutorial application from the public `dibanez/fastapi_tutorial` Git repository, builds a Python virtual environment, installs application requirements, and runs Uvicorn as a root-owned systemd service. It installs and starts local PostgreSQL and creates the `fastapi` role/database.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/pip/venv and Git installation; application checkout to `/opt/fastapi-tutorial`; PostgreSQL and contrib package installation; generated `.env`; systemd unit for Uvicorn on TCP 8000.

- **nginx-multisite**:
  - Description: Configures Nginx as a three-site HTTPS web server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It deploys static site pages, creates self-signed certificates, configures Nginx virtual hosts, enables host firewall and Fail2ban controls, applies sysctl hardening, and disables SSH root/password authentication.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration and service management; static content deployment; per-site TLS virtual hosts and development self-signed certificates; UFW default-deny policy with SSH/HTTP/HTTPS exceptions; Fail2ban; SSH hardening; sysctl hardening.

**CRITICAL PATH VERIFICATION:** All cookbook paths above are present in the supplied repository tree and their `metadata.rb` and primary `recipes/default.rb` files were reviewed. No Puppet modules, Salt states, or PowerShell modules were found.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbooks, and external Nginx, Memcached, and Redis cookbook constraints. It leaves `ssl_certificate` commented out despite that cookbook being included in the Policyfile.
- `Policyfile.rb`: Defines the `nginx-multisite-policy` run list and declares local cookbooks plus external `nginx`, `ssl_certificate`, `memcached`, and `redisio` dependencies. Replace this ordering and dependency mechanism with Ansible playbooks, roles, collections, and a `requirements.yml` only where collections are actually used.
- `Policyfile.lock.json`: Locks resolved cookbook versions: Memcached 6.1.0, Nginx 12.3.1, RedisIO 7.2.4, SELinux 6.2.4 (transitive), and SSL Certificate 2.1.0. Use it as the baseline for behavioral comparison; it also reveals an inconsistency with the Berksfile.
- `solo.rb`: Chef Solo cookbook-path and logging configuration. It is retired by the Ansible inventory, `ansible.cfg`, and role layout.
- `solo.json`: Chef run list and environment-specific Nginx/TLS/security attributes. Convert into version-controlled defaults and environment-specific `group_vars`; do not carry forward credentials found in source.
- `Vagrantfile`: Defines a `generic/fedora42` VM under the libvirt provider, with 2 GB RAM, two vCPUs, private IP `192.168.121.10`, rsync synchronization, and HTTP/HTTPS port forwards. Retain as a development test target, replacing the shell/Chef provisioner with `ansible_local` or host-run Ansible provisioning.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef through a remote curl-to-shell pipeline, installs Berkshelf, vendors cookbooks, and runs Chef Solo. Remove this Chef bootstrap in favor of Ansible installation/provisioning; its Debian package assumptions conflict with the configured Fedora box.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default Nginx site, TLS-path, UFW/Fail2ban, and SSH-hardening attributes. Treat as role defaults, with `solo.json` values as environment overrides.
- `cookbooks/nginx-multisite/templates/` and `files/`: Chef ERB templates and static site assets that must be converted to Jinja2 templates and role files after functional comparison.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: A custom Chef resource present in the cookbook. Its use was not established from the primary recipe review; assess whether it is used before reproducing it, as equivalent line editing is normally handled by `ansible.builtin.lineinfile`.
- `project-plan.md`: Documentation for the X2Ansible migration-tool concept, not active infrastructure configuration. It can inform process expectations but should not be migrated as infrastructure.

### Target Details

- **Operating System**: The declared development VM is Fedora 42. However, the bootstrap uses `apt-get`, the security role uses UFW, Nginx site paths use Debian-style `sites-available`/`sites-enabled`, service ownership assumes `www-data`, and the cookbook metadata supports Ubuntu 18.04+ and CentOS 7+. The target operating system is therefore inconsistent and must be selected before implementation. If no decision is made, use Red Hat Enterprise Linux 9 as the enterprise baseline, as required by the migration convention, and replace UFW/Debian layout assumptions accordingly.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; likely KVM/libvirt-backed virtualization.
- **Cloud Platform**: Not specified. No cloud provider configuration was found.

## Migration Approach

Create an Ansible repository with a top-level playbook such as `playbooks/site.yml`, inventories for development and future environments, and roles `nginx_multisite`, `cache`, and `fastapi_tutorial`. Keep environment values in inventory/group variables, use handlers for service reload/restart, and use fully qualified Ansible module names. Initially preserve the Chef run order—security/Nginx, cache, application—but explicitly model the application’s PostgreSQL prerequisite and ensure Nginx upstream routing is only added if the existing template demonstrates it.

Use Molecule or an equivalent Vagrant/libvirt test workflow to validate each role independently and then validate the full host. Establish acceptance tests for package/service state, listening ports, firewall reachability, rendered Nginx syntax, TLS permissions, database role/database state, static site availability, and FastAPI health. Assign an infrastructure owner for Nginx/security/cache, an application/database owner for FastAPI/PostgreSQL, and a security reviewer for SSH, firewall, certificates, and secret handling. Preserve a source-to-target traceability matrix during implementation and run a parallel non-production Chef-versus-Ansible comparison before retiring Chef.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (Chef >= 16.0)**: Retire Chef bootstrap, Solo configuration, run lists, Berkshelf vendor workflow, and Chef resource semantics. Use Ansible core modules, inventories, roles, handlers, and lint/testing in their place.
- **Chef Supermarket `nginx` (locked 12.3.1)**: The local Nginx cookbook directly installs/configures Nginx rather than visibly including this dependency. Replace with `ansible.builtin.package`, `template`, `file`, and `service`/`systemd`; retain the external cookbook only as behavioral reference until confirmed unused.
- **Chef Supermarket `memcached` (locked 6.1.0)**: Replace with OS package installation and `ansible.builtin.service`/`systemd`. Determine and explicitly set any service configuration that the external Chef cookbook applied but the local recipe did not expose.
- **Chef Supermarket `redisio` (locked 7.2.4)**: Replace with OS Redis packages and an explicitly managed Redis configuration template. Model authentication using Ansible Vault and use handlers to restart Redis. Reassess the Chef Ruby workaround instead of blindly deleting directives after rendering.
- **Chef Supermarket `selinux` (locked 6.2.4, transitive through RedisIO)**: It is a transitive lock dependency, but the intended Fedora/RHEL target requires an explicit SELinux decision. Manage enforcing/permissive policy, file contexts, ports, and booleans through `ansible.posix.selinux` and `community.general.sefcontext`/`restorecon` where applicable.
- **Chef Supermarket `ssl_certificate` (locked 2.1.0)**: It is declared in the Policyfile but not used by the reviewed local recipes and is commented in Berksfile. Do not migrate it automatically; replace the local OpenSSL self-signed certificate logic with `community.crypto` for development or a production PKI/ACME workflow after requirements are confirmed.
- **Public Git source `https://github.com/dibanez/fastapi_tutorial.git` (branch `main`)**: Replace Chef Git synchronization with `ansible.builtin.git`, preferably pinned to a reviewed commit or release rather than mutable `main`. Validate requirements and application packaging before deployment.
- **Python/PyPI dependencies in the application repository**: Manage a virtual environment through `ansible.builtin.pip` and a pinned requirements file, optionally via an approved internal package index. This dependency content was not available in the reviewed Chef repository.
- **PostgreSQL packages and local database**: Use distribution-specific PostgreSQL packages and `community.postgresql` modules for role/database/privilege management. The collection and its Python driver must be installed on the appropriate Ansible execution context.
- **OpenSSL, CA certificates, Fail2ban, firewall tooling, systemd, and sysctl**: Use package/service/template/sysctl modules. Select the firewall module by finalized platform: `community.general.ufw` for Ubuntu or `ansible.posix.firewalld` for RHEL/Fedora, rather than relying on raw commands.

### Security Considerations

- **Hardcoded Redis credential in `cache`**: `redis_secure_password_123` is embedded in the Chef recipe. Remove it from source history if possible, rotate it, store the replacement in Ansible Vault or an approved external secret manager, and render Redis configuration with restrictive ownership/mode.
- **Hardcoded PostgreSQL/application credential in `fastapi-tutorial`**: The cookbook creates the `fastapi` PostgreSQL user with `fastapi_password` and writes it in `DATABASE_URL` to `/opt/fastapi-tutorial/.env` with mode `0644`. Rotate this password; retrieve/store it through Ansible Vault or an external secret backend; set the environment file to a service-account-readable restrictive mode (normally `0600` or `0640`) and avoid logging it.
- **TLS certificates in `nginx-multisite`**: The source generates 2048-bit RSA, one-year, self-signed development certificates and stores private keys under `/etc/ssl/private` mode `0710`, with keys set to `0640` and group `ssl-cert`. Maintain least-privilege access but replace self-signed production use with organization PKI or ACME certificates, secure key deployment, renewal, and a reload handler. Certificate subject values are example values and must be replaced.
- **SSH hardening in `nginx-multisite`**: Root login and password authentication are disabled by direct `sed` edits. Use a managed drop-in configuration where supported, validate `sshd` syntax before reload, confirm key-based emergency access and console access, and roll out with a lockout-safe strategy.
- **Firewall and Fail2ban in `nginx-multisite`**: UFW is set to default deny and only SSH, HTTP, and HTTPS are allowed. This is security-positive but can disrupt provisioning/operations and is not native to the configured Fedora image. Define management CIDRs, IPv6 policy, and the RHEL/Fedora firewall implementation before enabling enforcement.
- **System hardening in `nginx-multisite`**: The sysctl and Fail2ban settings are rendered from templates not reviewed in detail. Preserve only settings validated against the chosen OS/kernel and application traffic profile; test for conflicts with container/runtime or cloud baselines.
- **Privilege model in `fastapi-tutorial`**: Uvicorn runs as `root`, despite the application directory being root-owned. Create a dedicated non-login service account, restrict writable paths, and use systemd sandboxing controls where compatible.
- **Supply-chain controls**: Chef installation uses `curl | bash`, Chef dependencies originate from Supermarket, the application tracks mutable `main`, and pip installation may resolve unpinned dependencies. The Ansible solution should use approved repositories, checksum/signature controls where feasible, pinned Git revisions and Python dependency versions, and CI vulnerability scanning.
- **Secrets inventory by module**: `cache` contains a hardcoded Redis password. `fastapi-tutorial` contains a hardcoded PostgreSQL password/connection URI in a world-readable environment file. `nginx-multisite` references and generates TLS private keys but does not contain an imported private-key secret. No Chef encrypted data bags or Chef Vault usage was found in the reviewed files.

### Technical Challenges

- **Contradictory platform assumptions**: Fedora 42/libvirt is declared, while provisioning uses APT and the Nginx/security recipes assume Ubuntu/Debian paths, UFW, `www-data`, and likely Debian service conventions. Decide whether to target Ubuntu or RHEL 9/Fedora before coding. Implement OS-specific variable maps and task files only if multi-platform support is an actual requirement.
- **External Chef cookbook behavior is partially opaque**: The cache role relies on `memcached` and `redisio`, whose full generated configuration is not in this repository. Capture the current node’s effective Memcached/Redis configuration and service state, then define the desired target configuration explicitly in Ansible.
- **Imperative Redis configuration workaround**: The Ruby block edits the generated `/etc/redis/6379.conf` after another cookbook manages it. Replace it with a single source-of-truth Jinja2 configuration and validate Redis syntax/startup; determine why those directives were removed before omitting them.
- **Database idempotency and packaging**: Shell `psql ... || true` commands mask both already-exists conditions and real failures. Use PostgreSQL Ansible modules with a privileged database connection, correct ownership/privileges, secure authentication, and explicit error handling. PostgreSQL version and host access policy are not specified.
- **Nginx integration ambiguity**: The application is exposed on port 8000, while Nginx virtual-host templates were not needed to establish the module purpose. Confirm whether the reviewed Nginx templates proxy any host to FastAPI or serve only static content, and add reverse-proxy/upstream, headers, and application health checks only where required.
- **Chef attribute precedence versus Ansible variables**: Cookbook defaults conflict with `solo.json` document roots (`/opt/server/...` versus `/var/www/...`). Define and document an Ansible variable precedence model and choose the intended values per environment.
- **Network and hostname test gap**: The Vagrant private address is `192.168.121.10`, but the provisioning script prints `192.168.56.10`. The sample domains also need DNS or `/etc/hosts` entries. Correct these inconsistencies and make test hostname resolution explicit.

### Migration Order

1. **Foundation and target-platform decision**: Select Ubuntu versus RHEL 9/Fedora, define inventory, Ansible version/collections, privilege escalation, Vagrant/libvirt test method, OS-specific variables, secret backend, and baseline validation. Do this before porting roles because platform differences affect nearly every cookbook.
2. **`nginx-multisite` security baseline**: Port package installation, Nginx rendering, static content, handlers, TLS development workflow, SSH hardening, Fail2ban, firewall, and sysctl as a tested role. Validate remote-access safety before enforcing firewall/SSH changes.
3. **`cache`**: Port Memcached and Redis with explicit package/version/configuration decisions. Replace the exposed Redis password with vaulted data and remove the post-render Ruby hack through a declarative Redis template.
4. **`fastapi-tutorial`**: Port PostgreSQL, database role/database, application checkout, virtual environment, dependencies, restricted environment file, dedicated service account, and systemd unit. Pin application dependencies and validate an application health endpoint.
5. **End-to-end integration and Chef retirement**: Validate virtual-host behavior, TLS, cache/database connectivity, host firewall paths, service recovery, idempotence, and rollback on the Vagrant/libvirt environment. Update operations documentation and decommission Policyfile/Berkshelf/Chef Solo provisioning only after acceptance.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks in scope; no Puppet, Salt, DSC, or PowerShell configuration is present in the supplied tree.
- The environment is currently intended primarily for local development/testing because it uses Vagrant, private networking, example DNS names, static test pages, self-signed certificates, and tutorial application code.
- Fedora 42 in `Vagrantfile` is an intention, not confirmed working behavior, because the bootstrap script invokes APT and Chef recipes use Debian/Ubuntu conventions.
- If the final OS is not specified, the proposed enterprise default is RHEL 9; this requires redesign of UFW and Debian Nginx filesystem/service-account assumptions rather than direct preservation.
- The policy lock is the most precise record of resolved external Chef versions; the divergence between Policyfile and Berksfile regarding `ssl_certificate` must be reconciled.
- The Nginx ERB templates, Fail2ban/sysctl contents, custom `lineinfile` resource use, external Chef cookbook internals, application requirements, PostgreSQL version, database network exposure, and FastAPI health/API behavior were not fully reviewed in this high-level survey and require implementation-stage confirmation.
- There is no defined production DNS, cloud provider, VM image pipeline, certificate authority, secret manager, CI/CD system, backup policy, observability stack, high availability requirement, or data migration requirement in the reviewed sources.
- Existing hardcoded credentials must be considered compromised for migration planning and rotated; Ansible Vault is a minimum option, with an organizational secret manager preferred for production.
- The desired end state is Ansible-managed configuration rather than a wrapper that continues to invoke Chef or Chef Supermarket cookbooks.
