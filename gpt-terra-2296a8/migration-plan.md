# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo / Policyfile configuration for a small but cross-cutting web application stack: hardened Nginx multi-site HTTPS hosting, Redis and Memcached caching, and a FastAPI application backed by local PostgreSQL. Three local Chef cookbooks are applied in one ordered run list, with four Supermarket cookbook dependencies resolved in the policy lock. The codebase is compact, but migration risk is moderate because it mixes operating-system assumptions, external application source/dependency resolution, network security changes, TLS private keys, and hardcoded service credentials.

A practical implementation and validation effort is approximately **2–3 engineer-weeks**, assuming a non-production development environment is available. Allow additional time for production certificate, database credential, operating-system, and firewall decisions. Coordinate the work through a shared variable/secrets design, role interface contract, and staged parity tests rather than translating Chef resources one-for-one.

## Module Migration Plan

This repository contains **Chef cookbooks** that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths are present in the supplied repository tree are included below.

- **nginx-multisite**:
  - Description: Installs and configures Nginx as a three-site static-content web server for `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It provisions Nginx and security configuration from templates, creates document roots and index pages, creates site definitions and enabled-site links, removes the default site, and enables Nginx.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Self-signed RSA TLS certificates per enabled site; Nginx virtual hosts and static files; Fail2ban; UFW default-deny firewall with SSH/HTTP/HTTPS access; sysctl hardening; SSH root-login and password-authentication disabling.

- **cache**:
  - Description: Installs Memcached and Redis, configures a Redis instance on port 6379 with authentication, creates the Redis log directory, then enables Redis. It also uses a Ruby block to remove selected replication and client-buffer directives from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached service through the upstream cookbook; Redis service and log directory; Redis `requirepass`; post-processing workaround for `/etc/redis/6379.conf`.

- **fastapi-tutorial**:
  - Description: Deploys the FastAPI tutorial application from its public Git repository, creates a Python virtual environment, installs Python requirements, installs and starts PostgreSQL, creates a PostgreSQL user and database, writes an application environment file, and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Git checkout of `dibanez/fastapi_tutorial` branch `main`; Python 3 virtual environment; local PostgreSQL database provisioning; `.env` configuration; continuously restarted root-run systemd service.

### Infrastructure Files

- `Berksfile`: Berkshelf dependency source and local cookbook declarations. It requests upstream `nginx`, `memcached`, and `redisio`; `ssl_certificate` is commented out here.
- `Policyfile.rb`: Declares the `nginx-multisite-policy` run list in this order: Nginx/security, cache, then FastAPI. It pins the intended dependency constraints and includes `ssl_certificate`, even though the local recipes generate certificates with OpenSSL directly.
- `Policyfile.lock.json`: Locked dependency resolution for repeatable Chef runs. Confirmed resolved versions include Memcached 6.1.0, Nginx 12.3.1, Redisio 7.2.4, SSL Certificate 2.1.0, and transitive SELinux 6.2.4. Preserve functional intent rather than carrying these Chef artifacts into Ansible.
- `solo.rb`: Chef Solo cache, cookbook path, and logging configuration. Replace with an Ansible inventory, `ansible.cfg`, and role/playbook layout.
- `solo.json`: Node attributes for the three Nginx sites, TLS directories, and security toggles. Migrate these to environment-specific `group_vars`/`host_vars`; reconcile its document-root values with the cookbook defaults.
- `Vagrantfile`: Local test VM definition using `generic/fedora42`, private IP `192.168.121.10`, port forwarding (80→8080 and 443→8443), rsync sharing, and the libvirt provider (2 GB RAM, 2 vCPUs). Retain or replace it as the Ansible integration-test environment.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. It uses `apt-get`, which conflicts with the Fedora Vagrant box and must be replaced with an OS-correct Ansible bootstrap/provisioning path.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default Nginx virtual-host, TLS, and security attribute values. Its document roots (`/opt/server/...`) differ from `solo.json` (`/var/www/...`); make the Ansible source of truth explicit.
- `cookbooks/nginx-multisite/templates/`: Nginx, site, security, Fail2ban, and sysctl templates that must be converted to Jinja2 with behavior verified in the target distribution.
- `cookbooks/nginx-multisite/files/default/`: Static index content for the three virtual hosts; migrate using the Ansible `copy` module or role files.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the repository but not invoked by the reviewed cookbook entrypoint recipes. Assess whether it is unused before migration; Ansible has built-in `lineinfile` if it is later found to be required.

### Target Details

- **Operating System**: The declared cookbook support matrix is Ubuntu 18.04+ and CentOS 7+, while the Vagrant box is Fedora 42. The provisioning script assumes Debian/Ubuntu (`apt-get`, `www-data`, UFW, and an `ssh` service name), whereas the policy lock includes a SELinux dependency consistent with Red Hat-family support. The target OS is therefore **ambiguous and currently internally inconsistent**. Select and test a supported target explicitly before implementation; Fedora 42 cannot safely be treated as equivalent to Ubuntu or CentOS 7.
- **Virtual Machine Technology**: Vagrant with the **libvirt/KVM** provider is explicitly configured.
- **Cloud Platform**: Not specified. No cloud provider tooling or metadata integration was identified.

## Migration Approach

Build a conventional Ansible repository with a top-level playbook assigning roles such as `baseline_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep environment-specific virtual-host definitions and runtime values in inventory variables. Use handlers for Nginx, Fail2ban, SSH, sysctl, systemd daemon reload, Redis, PostgreSQL, and FastAPI restarts. First establish the chosen OS support matrix and package/service naming, then implement idempotent roles and validate them with a fresh Vagrant/libvirt VM.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Retire `chef-solo`, Berkshelf, `solo.rb`, and node JSON in favor of Ansible playbooks, inventories, collections, and role variables.
- **Berkshelf and Chef Supermarket**: No Ansible equivalent is required for package/service management; use supported Ansible collections only where their APIs add value and pin collection versions in `collections/requirements.yml` if used.
- **Chef `memcached` cookbook (locked 6.1.0)**: Replace with OS package installation and `ansible.builtin.service`/`systemd` management. Capture any upstream cookbook defaults that are required but not visible in the local recipe before cutover.
- **Chef `redisio` cookbook (locked 7.2.4)**: Replace with distribution Redis packages, a managed Redis configuration template, protected secret variable for `requirepass`, file ownership/mode management, and a Redis handler. Re-evaluate the Chef Ruby configuration-edit workaround; encode only validated required settings in the complete Jinja2 template.
- **Chef `nginx` cookbook (locked 12.3.1)**: The local recipe directly installs and configures Nginx, so migrate it using package, template, file/copy, and service tasks rather than retaining the Chef cookbook abstraction.
- **Chef `ssl_certificate` cookbook (locked 2.1.0)**: It is policy-resolved but no reviewed local recipe includes it; TLS is generated via OpenSSL commands. Remove it unless further requirements demonstrate use. Use `community.crypto` certificate/key modules for development self-signed certificates, or integrate an approved production PKI/certificate workflow.
- **PostgreSQL and Python packages**: Use distribution-specific package maps and `community.postgresql` modules for roles, databases, and privileges. Use `ansible.builtin.git`, `ansible.builtin.pip` with the virtualenv path, and `ansible.builtin.systemd` for FastAPI deployment.
- **External Git repository and Python requirements**: The application is fetched from `https://github.com/dibanez/fastapi_tutorial.git` at mutable branch `main`; pin a reviewed commit or release and use an internal mirror/artifact source for controlled deployments. Pin and scan Python dependencies from the application’s requirements file.
- **OpenSSL / CA certificates, Fail2ban, UFW, and sysctl**: Map to package and platform-specific Ansible tasks. UFW is Debian-focused; use `community.general.ufw` only on Debian-family hosts and a Red Hat/Fedora-compatible firewall implementation (such as `ansible.posix.firewalld`) where applicable.

### Security Considerations

- **Hardcoded Redis credential (`cache`)**: `redis_secure_password_123` is embedded in the recipe. Move it to Ansible Vault or an external secret manager, rotate it before migration, enforce restrictive Redis configuration permissions, and avoid exposing it in logs or rendered reports.
- **Hardcoded PostgreSQL/application credential (`fastapi-tutorial`)**: The database password `fastapi_password` is embedded in SQL and in `/opt/fastapi-tutorial/.env`. Replace it with a unique vaulted/generated secret; render `.env` owned by the application account with mode `0600`, and rotate the current credential.
- **TLS private keys (`nginx-multisite`)**: The current code generates 2048-bit self-signed private keys in `/etc/ssl/private`, mode `0640`, group `ssl-cert`. Development self-signed certificates cause browser trust warnings and are unsuitable for public production endpoints. Define a production certificate issuer, renewal mechanism, key escrow/rotation policy, and access group; never commit private keys.
- **SSH hardening (`nginx-multisite`)**: Root login and password authentication are disabled conditionally. Before applying this in Ansible, confirm that each administrator has tested key-based access and an out-of-band recovery route; otherwise automation can lock out operators. Use `sshd_config.d` where supported and validate configuration before restart.
- **Firewall and intrusion protection (`nginx-multisite`)**: Default-deny UFW plus allow rules for SSH, HTTP, and HTTPS, and enabled Fail2ban, must be translated without interrupting management access. Stage firewall tasks, retain the selected Ansible control port/source policy, and test rules under the selected OS firewall stack.
- **System/kernel and Nginx hardening (`nginx-multisite`)**: Preserve and review the sysctl and Nginx security template semantics with security engineering; OS defaults and supported directives differ by distribution and Nginx version.
- **Application privilege (`fastapi-tutorial`)**: The FastAPI systemd unit runs as `root`, and `.env` is world-readable (`0644`). Create a dedicated non-login application user, restrict application/configuration ownership, and add systemd sandboxing appropriate to the application.
- **Supply-chain controls (`fastapi-tutorial`, provisioning)**: The current bootstrap curls and executes the Chef installer and installs unpinned application dependencies. Remove Chef bootstrap from the target process; pin Git revision and Python artifacts, verify sources, and route deployments through approved repositories.
- **Vault/secrets management**: Visible credential patterns are Redis `requirepass` in **cache**, PostgreSQL user password/database URL in **fastapi-tutorial**, and TLS private-key handling in **nginx-multisite**. Store all new runtime secrets in Ansible Vault or the organization’s secret manager, separate secrets by environment, and ensure CI logs redact them.

### Technical Challenges

- **Conflicting platform assumptions**: Fedora 42/libvirt is declared, but the provisioning and several configuration choices are Ubuntu/Debian-centric; cookbook metadata additionally names CentOS 7. Decide the production OS and supported versions before selecting package names, service names, users/groups, firewall modules, Nginx layouts, SELinux policy, and test images.
- **Configuration source conflicts**: `solo.json` overrides default Nginx document roots with values that differ from `attributes/default.rb`. Define a single Ansible variable contract and explicit variable precedence, then test rendered vhosts and files.
- **Chef upstream behavior is partially opaque**: The local cache recipe delegates installation/configuration to external `memcached` and `redisio` cookbooks. The migration must inventory the effective deployed Redis/Memcached configuration on a reference VM before reproducing only the intended behavior.
- **Imperative/non-idempotent-looking Chef shell operations**: Database creation uses shell commands with `|| true`, SSH settings are modified with `sed`, UFW uses shell checks, and Redis is edited with Ruby text substitutions. Use declarative Ansible modules/templates plus `validate`/handlers to obtain reliable idempotence and clear failure behavior.
- **Application reproducibility and service behavior**: Pulling `main` makes deployments non-deterministic; the Python requirements and FastAPI application internals are outside this repository. Pin an immutable application revision, define upgrade/rollback procedures, confirm the application’s database migrations and environment requirements, and use health checks before promoting service restarts.
- **Service exposure and integration gap**: Nginx serves static multi-sites on 80/443 while FastAPI listens on 8000; the reviewed Nginx entrypoint does not demonstrate proxying to FastAPI. Confirm intended traffic routing, DNS, TLS hostnames, and whether an application virtual host/reverse proxy is missing before declaring parity.

### Migration Order

1. **Foundation and target contract**: Select the target OS/firewall/SELinux posture, create inventory and variable schemas, replace the Vagrant provisioning flow with an Ansible test playbook, and establish Vault/external-secret integration. Resolve the document-root and hostname/DNS assumptions.
2. **Nginx static multi-site baseline**: Migrate Nginx packages, Jinja2 templates, site directories/files, vhost enablement, handlers, and development TLS. Verify HTTP/HTTPS routing and port forwarding in a disposable environment before applying security enforcement.
3. **Security controls**: Implement and test Fail2ban, sysctl, firewall, SSH hardening, and certificate/private-key access controls. Schedule this after validated administrative connectivity and with rollback/recovery procedures.
4. **Cache services**: Migrate Memcached and Redis with a vaulted Redis password and a declarative Redis configuration. Compare service ports, authentication, logging, persistence/replication behavior, and client connectivity against a Chef-built reference.
5. **PostgreSQL and FastAPI application**: Provision database roles/databases with secure credentials, deploy a pinned application artifact into a virtual environment, migrate `.env` and systemd configuration to a dedicated service account, and validate startup, database connectivity, restart behavior, and any intended Nginx integration.
6. **Cutover and operationalization**: Run idempotence tests, security review, package/vulnerability checks, acceptance tests for all sites and service endpoints, documentation/knowledge transfer, then execute a staged deployment with rollback artifacts.

### Assumptions

- Only Chef technology was identified in the supplied tree; no Puppet manifests, Salt states, or PowerShell modules were present.
- The three directories under `cookbooks/` are the complete local cookbook inventory supplied for this review.
- Chef Policyfile ordering reflects intended deployment ordering, but no explicit runtime dependency between Nginx, cache, and FastAPI is declared beyond that run list.
- The Vagrant/libvirt machine is a development or test environment, not evidence of the production platform.
- The intended target OS is not confirmed. The plan does not assume Fedora, Ubuntu, CentOS, or RHEL until stakeholders select a supported target; this takes precedence over a generic default.
- The existing `Vagrantfile` Fedora box and `vagrant-provision.sh` use of `apt-get` cannot both work without additional bootstrap changes.
- The current configuration expects `www-data`, UFW, and an `ssh` service identifier, which may require OS-specific mappings or changes on Fedora/RHEL-family systems.
- TLS certificates are explicitly described as development self-signed certificates. A production certificate authority, DNS ownership, and renewal mechanism are not provided.
- The external FastAPI repository, its Python requirements, application schema/migrations, and its expected production process model were not included and require separate application-owner validation.
- The FastAPI database SQL is intended to be local PostgreSQL and can be replaced with idempotent database modules; existing database contents, backup/restore needs, and migration procedures are unknown.
- The custom Chef `lineinfile` resource is assumed not to affect the reviewed default execution path because it is not referenced there; confirm repository-wide usage before retiring it.
- The lock file’s resolved `ssl_certificate` and `selinux` cookbooks may be transitive or policy artifacts; direct local recipe use was not observed in the reviewed entrypoints.
- No CI/CD pipeline, production inventory, cloud provider, DNS automation, monitoring, log shipping, backup policy, or secret-management platform was supplied. These require decisions and ownership assignments before production rollout.
