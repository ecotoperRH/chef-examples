# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile configuration for a small single-node web/application stack. It contains three local Chef cookbooks, coordinated by `nginx-multisite-policy`: an Nginx multi-site HTTPS edge with host hardening, Memcached and Redis caching, and a FastAPI tutorial application backed by local PostgreSQL. The stack is compact (three local cookbooks), but migration complexity is **moderate** because it combines service orchestration, generated Nginx/Fail2ban/sysctl configuration, TLS key handling, firewall and SSH lockout-sensitive changes, third-party application dependency installation, and several OS-family inconsistencies.

A staged migration by one infrastructure engineer with application/security review is estimated at **2–3 weeks**: discovery and target decisions (2–3 days), role implementation (4–6 days), test-environment validation (3–4 days), and operational/security acceptance plus cutover documentation (2–4 days). This estimate excludes remediation of upstream application dependencies or a decision to replace development self-signed certificates with production PKI.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and enables local Memcached and Redis services. Redis is configured for TCP port 6379 with password authentication, creates `/var/log/redis`, and applies a post-install Ruby edit to remove selected replication-related configuration directives before enabling Redis.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion, Redis authentication, Redis logging directory, Redis service enablement, imperative cleanup of generated Redis replication settings.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from the `main` Git branch under `/opt/fastapi-tutorial`, creates a Python virtual environment, installs its requirements, installs and starts local PostgreSQL, provisions the `fastapi` database/user, and runs Uvicorn as a root-owned systemd service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3 and PostgreSQL package installation, Git deployment, venv/pip setup, database bootstrap, generated `.env`, systemd unit creation and service management.

- **nginx-multisite**:
  - Description: Configures an Nginx front end for the `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local` sites; deploys static index files; creates per-site TLS virtual-host configuration and certificates; and applies host protections including Fail2ban, UFW, kernel sysctl settings, and SSH root/password-login restrictions.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx global/security configuration templates, site configuration/symlinks and static content, self-signed RSA-2048 TLS certificates, Fail2ban jail configuration, UFW allow rules for SSH/HTTP/HTTPS, SSH hardening, and sysctl configuration.

**CRITICAL PATH VERIFICATION:**
All inventory paths above were present in the supplied repository tree and their Chef `metadata.rb` and primary/default recipe were reviewed. No Puppet manifests, Salt states, or PowerShell module/script entry points were present in the supplied tree.

### Infrastructure Files

- `Berksfile`: Defines local cookbook paths and Supermarket sources. It requests `nginx`, `memcached`, and `redisio`; the `ssl_certificate` line is commented here, which differs from the Policyfile.
- `Policyfile.rb`: Declares the intended converged run list—`nginx-multisite::default`, `cache::default`, then `fastapi-tutorial::default`—and pins requested external cookbook constraints.
- `Policyfile.lock.json`: Captures resolved versions: Memcached 6.1.0, Nginx 12.3.1, Redisio 7.2.4, Selinux 6.2.4 (transitive), and SSL Certificate 2.1.0. This is the authoritative observed dependency resolution, but it conflicts with the commented Berksfile SSL dependency and should be reconciled before migration.
- `solo.rb`: Chef Solo paths and logging configuration. It has no direct Ansible equivalent; replace execution with inventories, playbooks, role paths, and `ansible.cfg` as needed.
- `solo.json`: Chef node attributes defining three SSL-enabled sites, certificate/key directory locations, and enabled security/SSH policy. Convert these to Ansible group/host variables, with environment-specific values separated from role defaults.
- `Vagrantfile`: Local test topology using `generic/fedora42`, libvirt, 2 GB RAM, two CPUs, static private IP `192.168.121.10`, and host forwarding for ports 80/443. Preserve or replace with an Ansible-driven Vagrant test target; the libvirt platform is useful for acceptance testing.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef/Berkshelf, vendors cookbooks, and runs Chef Solo. Replace with minimal Python/Ansible bootstrap or Vagrant's Ansible provisioner. Its Ubuntu/Debian commands conflict with the Fedora Vagrant box.
- `cookbooks/nginx-multisite/attributes/default.rb`: Role-default-like site and security values. Move to role defaults while overriding environment-specific hostnames, document roots, and TLS settings in inventory variables.
- `cookbooks/nginx-multisite/templates/default/`: ERB templates for Nginx, virtual hosts, security directives, Fail2ban, and sysctl. Convert to Jinja2 templates after rendering comparison tests.
- `cookbooks/nginx-multisite/files/default/`: Static per-site index pages for test, CI, and status virtual hosts. Migrate with Ansible `copy` tasks or retain as role files.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: A custom Chef resource exists but is not referenced by the reviewed primary recipes. Determine whether it is unused or invoked outside the visible run list before deciding whether an Ansible `lineinfile` equivalent is required.
- `project-plan.md`: Documentation for an unrelated X2Ansible migration tool specification; it is not infrastructure configuration to migrate.

### Target Details

- **Operating System**: The cookbook metadata supports Ubuntu 18.04+ and CentOS 7+. The actual provisioning script uses `apt-get`, and the Nginx site layout (`/etc/nginx/sites-available` and `sites-enabled`), UFW, `www-data`, and SSH service name strongly indicate an intended **Ubuntu/Debian-family** target. However, `Vagrantfile` selects `generic/fedora42`, while its provisioner would fail there because it invokes `apt-get`; Redis package/service paths and the Nginx layout also need distribution validation. Standardize the migration target—preferably a supported Ubuntu LTS—before implementation rather than defaulting to RHEL 9.
- **Virtual Machine Technology**: Vagrant with the **libvirt** provider. The Vagrant test box is Fedora 42, but this conflicts with the Chef configuration assumptions.
- **Cloud Platform**: Not specified. No AWS, Azure, GCP, or cloud metadata/tooling configuration was observed.

## Migration Approach

Build a conventional Ansible repository with an inventory, environment group variables, and distinct roles such as `nginx_multisite`, `cache`, and `fastapi_tutorial`; optionally factor SSH/firewall/sysctl work into a reusable `host_security` role. Use one ordered site playbook that preserves the present Policyfile intent but makes dependencies explicit: base security and package prerequisites, caching/database services, application deployment, then Nginx/TLS. Avoid a literal Chef-resource translation: use idempotent Ansible modules, handlers, and explicit validation commands.

Coordinate work through agreed variable contracts and rendered-configuration comparison. The platform owner should first choose the supported OS and package/service naming; the security owner must approve firewall, SSH, TLS, and secret handling; and the application owner must validate the Git revision, Python dependency lock strategy, database schema/bootstrap expectations, and Uvicorn runtime configuration. Maintain a shared acceptance checklist covering all three hostnames, HTTP-to-HTTPS behavior if applicable, PostgreSQL connectivity, Redis authentication, firewall access, service persistence, and rollback.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (Chef >= 16.0)**: Remove Chef bootstrap, Solo JSON, and convergence from operations. Use `ansible-core` with an inventory and role-based playbooks; execute from CI or an approved control node.
- **Berkshelf and Chef Supermarket**: No longer required after migration. Preserve the locked behavior rather than importing Chef cookbook abstractions verbatim.
- **memcached (Chef cookbook 6.1.0)**: Replace with distribution packages and Ansible `package`/`service` tasks. Establish the intended Memcached listener, memory, and access controls because the local recipe merely includes the external cookbook and does not show its resulting configuration.
- **redisio (Chef cookbook 7.2.4)**: Replace with distribution Redis packages, managed Redis configuration, and `systemd` service tasks. Implement `requirepass` using an Ansible Vault-backed variable. Explicitly decide whether the removed replication directives were workaround-only or represent required final behavior.
- **nginx (Chef cookbook 12.3.1)**: Replace with Nginx distribution packages, Jinja2-managed global configuration and per-site files, symlink/state management appropriate to the selected OS, and handlers that validate (`nginx -t`) before reload.
- **ssl_certificate (Chef cookbook 2.1.0)**: It is present in the locked Policyfile but is not used by the reviewed local recipes, which generate certificates directly with OpenSSL. Do not migrate it as a role dependency unless a pre-migration review finds a use outside the visible recipes. Use `community.crypto` for self-signed development certificates or integrate the approved PKI/ACME process for production.
- **selinux (Chef cookbook 6.2.4)**: A transitive Redisio dependency in the lockfile. Its relevance depends on the final OS. It is not required for an Ubuntu target; for RHEL-family targets, define required SELinux labels/booleans explicitly rather than assuming Chef cookbook behavior.
- **GitHub repository `https://github.com/dibanez/fastapi_tutorial.git`**: Pin a reviewed commit or release rather than continuously deploying mutable `main`. Ensure target hosts have controlled network/proxy access or mirror the source artifact internally.
- **Python/pip application requirements**: The requirements file is fetched from the external Git repository and is not locked in this infrastructure repository. Use a lockfile, internal package repository, hashes, or a built artifact to make deployments repeatable and support vulnerability management.
- **PostgreSQL**: Replace shell `psql` invocations with `community.postgresql` database/user modules where feasible, using a privileged local connection and explicit database/user state. Confirm PostgreSQL major version, authentication policy, and schema migration ownership.

### Security Considerations

- **Hardcoded Redis credential**: `cache::default` embeds a Redis password in source. Move it to Ansible Vault or an external secret manager, rotate it during migration, set restrictive Redis configuration permissions, and ensure the application is updated if it consumes this password.
- **Hardcoded PostgreSQL/FastAPI credential and exposed environment file**: The `fastapi` password appears both in database-creation shell commands and in `/opt/fastapi-tutorial/.env`; the file is mode `0644`, making its database URL world-readable. Store the credential in Vault/external secrets, rotate it, create `.env` with the application service account and `0600`, and avoid credentials in process-visible command lines.
- **TLS private keys and self-signed certificates**: The Nginx cookbook creates self-signed, 365-day RSA-2048 keys under `/etc/ssl/private` with `root:ssl-cert` ownership and mode `0640`; certificates are development-oriented and cause browser warnings. Preserve restrictive private-key access, replace self-signed certificates with organization PKI/ACME-issued certificates for production, and define renewal/rotation and reload handling.
- **SSH hardening and firewall changes**: The supplied attributes disable root login and password authentication; UFW defaults to deny and permits SSH/HTTP/HTTPS. Apply Ansible changes only after verifying key-based administrative access, management network requirements, port/service naming, and a console/rollback path to prevent host lockout. Use `community.general.ufw` only for Ubuntu/Debian; use the appropriate firewalld modules for RHEL/Fedora.
- **Host hardening configuration**: Fail2ban and sysctl settings are rendered from templates. Review the actual template policy with the security team, apply configuration validation, and ensure values are compatible with the selected OS/kernel.
- **Network exposure and application runtime**: Uvicorn binds to `0.0.0.0:8000` and runs as `root`. In the target design, create a dedicated non-login application user, bind the application to localhost or a protected internal network behind Nginx, and ensure port 8000 is not publicly allowed.
- **Supply chain and privilege**: The bootstrap downloads and executes Chef's Omnitruck installer and installs Berkshelf at runtime; the application deploys an unpinned Git branch and pip dependencies. Eliminate runtime bootstrap downloads in favor of versioned Ansible execution environments and vetted OS/package/application artifacts.
- **Credential patterns by module**:
  - `cache`: A visible hardcoded Redis `requirepass` value.
  - `fastapi-tutorial`: A visible hardcoded PostgreSQL application password and database URL in a world-readable `.env` file.
  - `nginx-multisite`: No static secret value was found, but it generates private TLS keys and configures protected key directories. It also enforces SSH access policy.

### Technical Challenges

- **OS and package-management contradiction**: The declared Vagrant box is Fedora 42 while `vagrant-provision.sh` uses APT; Nginx paths, UFW, `www-data`, and `ssh` service naming are Debian-oriented. Mitigation: make an explicit platform decision before role implementation, test on a matching base image, and use OS-specific variable files/tasks only if multi-platform support is truly required.
- **External Chef cookbook behavior is only partially visible locally**: Local recipes delegate key behavior to `memcached` and `redisio`, while the lockfile identifies exact cookbook versions. Mitigation: inventory the final Chef-converged configuration or a representative running node (packages, unit names, listeners, Redis config, SELinux state) and define desired Ansible state directly.
- **Imperative/non-idempotent Chef patterns**: The Redis `ruby_block` edits configuration with regex replacement; PostgreSQL uses shell commands with `|| true`; SSH uses `sed`; and OpenSSL certificate generation is command-based. Mitigation: replace these with managed templates and purpose-built Ansible modules, guarded commands only where no module exists, and idempotence tests on repeated runs.
- **Template and virtual-host parity**: Nginx, Fail2ban, sysctl, and site behavior is carried in ERB templates that were not exhaustively reviewed for this high-level survey. Mitigation: convert templates to Jinja2, retain role variables for each site, compare rendered output, and run syntax tests (`nginx -t`, relevant Fail2ban/sysctl checks) before service handlers.
- **Application lifecycle is underspecified**: The recipe installs requirements and starts Uvicorn but does not show schema migration, process workers, health checks, reverse proxy routing, or an application revision pin. Mitigation: obtain application owner decisions and add health checks, a deployment artifact/version policy, a non-root account, and an explicit database migration step if needed.
- **Order and readiness dependencies**: FastAPI requires PostgreSQL availability; Nginx may need upstream routing details not visible in the entrypoint; service reloads must follow validated configuration. Mitigation: model explicit role dependencies, use handlers, `wait_for`/health checks, and integration tests rather than rely only on Chef run-list ordering.

### Migration Order

1. **Foundation and host-security baseline (extracted from `nginx-multisite`)**: Select and build the supported OS test image; establish inventories, Vault/secret integration, package repository policy, service account standards, firewall rollout safeguards, SSH access verification, and sysctl/Fail2ban review. This is a prerequisite because later services rely on secure host access and OS-specific behavior.
2. **cache**: Implement Memcached and Redis roles with managed configuration, Vault-backed Redis authentication, and service/listener tests. Validate the replacement for the existing Redis replication-directive workaround and any expected application consumption.
3. **fastapi-tutorial**: Implement PostgreSQL provisioning and the FastAPI deployment role with an immutable application revision, protected environment configuration, dedicated service user, systemd unit, and local health check. Validate database connectivity and startup before publishing through Nginx.
4. **nginx-multisite**: Convert Nginx templates, static site content, virtual-host activation, certificate management, and controlled reload handlers. Integrate the FastAPI upstream only after its expected Nginx routing is confirmed; validate each of the three declared hostnames and TLS behavior.
5. **End-to-end cutover and retirement**: Run repeated Ansible idempotence tests in libvirt/Vagrant or the chosen target, conduct security/application acceptance, document rollback, switch operational automation, then remove Chef Solo/Berkshelf bootstrap dependencies.

### Assumptions

- The repository is a Chef-only infrastructure repository; no Puppet, Salt, PowerShell, Terraform, Kubernetes, or cloud-provider configuration was present in the supplied tree.
- The three local cookbook directories are the complete module/cookbook inventory within the supplied tree.
- `Policyfile.rb` expresses the intended deployment order; `solo.json` is the active Chef Solo attribute source. The repository does not state whether Policyfile and Berkshelf/Solo workflows are both actively used.
- The intended production OS is not definitively specified. Ubuntu/Debian is inferred from the configuration, despite the Fedora 42 Vagrant box. A supported OS version must be chosen before migration.
- The target is a single VM/node unless stakeholders provide an inventory or scaling architecture; no clustering, load balancer, or cloud platform is configured here.
- The externally sourced `nginx` and `ssl_certificate` cookbooks are policy dependencies, but the reviewed local Nginx and TLS recipes do not include them. Their actual runtime relevance must be verified from a converged node or full Chef dependency source.
- The contents of ERB templates and custom resource implementation were not reviewed in full, consistent with this high-level plan. Their rendered behavior requires parity validation during detailed role design.
- The FastAPI application repository, its requirements, expected reverse-proxy routing, database schema process, and operational health endpoint are outside this repository and require application-team confirmation.
- The visible Redis and PostgreSQL passwords are non-production examples only; regardless, they must be treated as exposed credentials and rotated rather than copied into Ansible.
- Self-signed TLS certificates are assumed to be a development/test mechanism because the provisioner explicitly warns of SSL warnings. Production certificate authority, DNS ownership, and renewal requirements are not specified.
- No CI/CD pipeline, existing Ansible controller, secret manager, source artifact mirror, or production rollback process is supplied; these must be selected and documented as migration work.
