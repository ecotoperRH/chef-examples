# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile configuration composed of three local Chef cookbooks and Supermarket dependencies. It provisions a development virtual machine as a hardened, SSL-enabled Nginx multi-site host with Redis and Memcached caching and a FastAPI tutorial application backed by local PostgreSQL. The migration is moderate in complexity: most work is conventional package, service, template, firewall, and systemd automation, while certificate handling, host-hardening changes, external application source/dependency reproducibility, and database credentials require deliberate redesign.

A focused two-person migration team can create an initial Ansible implementation and automated verification in approximately **2–3 weeks**, assuming a target OS decision is made promptly. Allow **3–5 weeks** for production-ready secret management, certificate automation, OS portability, CI validation, and environment-specific testing. The Chef repository is internally inconsistent about its operating system, which must be resolved before implementation.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **nginx-multisite**:
  - Description: Configures an Nginx web server hosting three static virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), redirects HTTP to HTTPS, generates development self-signed certificates, deploys site content, and applies web/host security controls.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx installation and service management; per-site document roots, content, configuration, and enabled-site links; TLS 1.2/1.3 configuration; self-signed certificate/key generation; HTTP-to-HTTPS redirects; HSTS and browser security headers; gzip; Fail2ban; UFW rules; SSH hardening; and kernel sysctl hardening.

- **cache**:
  - Description: Installs and enables Memcached and Redis, configures Redis on port 6379 with password authentication, creates the Redis log directory, and applies a post-install Ruby configuration workaround before enabling Redis.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: `memcached` cookbook inclusion; `redisio` server configuration; Redis authentication; Redis service enablement; and direct mutation of `/etc/redis/6379.conf` to remove replica-related settings.

- **fastapi-tutorial**:
  - Description: Deploys a FastAPI tutorial application from a public Git repository, creates a Python virtual environment, installs Python dependencies, provisions local PostgreSQL, writes application database settings, and runs Uvicorn under a systemd service.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python, Git, PostgreSQL, and build-library package installation; Git checkout of `dibanez/fastapi_tutorial` at `main`; virtualenv and `pip` requirements installation; PostgreSQL database/user/grant creation; `.env` generation; and an enabled `fastapi-tutorial` systemd unit listening on port 8000.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, all three local cookbooks, and external cookbook constraints. It is replaced by Ansible collections/roles and controlled Python/package dependencies; it also differs from the Policyfile by commenting out `ssl_certificate`.
- `Policyfile.rb`: Defines the intended Chef policy and run list: `nginx-multisite::default`, `cache::default`, then `fastapi-tutorial::default`. Use this order as an initial behavioral baseline, while separating reusable Ansible roles from environment playbooks.
- `Policyfile.lock.json`: Locks resolved cookbook versions: Nginx 12.3.1, Memcached 6.1.0, Redisio 7.2.4, SSL Certificate 2.1.0, and transitive SELinux 6.2.4. Use it to record the source baseline, not as a direct Ansible dependency; validate the required package/service behavior against supported target OS package versions.
- `solo.rb`: Chef Solo configuration pointing at `/chef-repo/cookbooks` and vendored cookbooks. It has no Ansible equivalent; replace it with an Ansible inventory, `ansible.cfg`, role requirements, and execution documentation.
- `solo.json`: Supplies the Chef run list and overrides Nginx site document roots to `/var/www/...`, while cookbook defaults specify `/opt/server/...`. Model these as Ansible environment/group variables with a single authoritative source.
- `Vagrantfile`: Development topology: `generic/fedora42`, Libvirt, 2 vCPUs, 2 GB memory, private IP `192.168.121.10`, and forwarded HTTP/HTTPS ports. Preserve only if Vagrant/Libvirt remains part of the test strategy; use it to create a repeatable Ansible molecule or Vagrant test target.
- `vagrant-provision.sh`: Bootstrap shell script that uses `apt-get`, installs Chef through a remote curl pipe, installs Berkshelf, vendors dependencies, and runs Chef Solo. Retire it in favor of a minimal Ansible control-node/bootstrap process. Its Debian package commands conflict with the Fedora Vagrant box and must not be copied forward.
- `cookbooks/nginx-multisite/attributes/default.rb`: Baseline Chef attributes for sites, certificate paths, and security toggles. Translate to role defaults, with site inventory and environment values in `group_vars`/`host_vars` or an approved external configuration source.
- `cookbooks/nginx-multisite/templates/default/*.erb`: Nginx, per-site TLS/security-header, Fail2ban, and sysctl configuration templates. Convert to Jinja2 templates after syntax and platform validation.
- `cookbooks/nginx-multisite/files/default/{test,ci,status}/index.html`: Static test-site assets to deploy through the Nginx role or a separate content deployment role.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the cookbook tree but not invoked by the reviewed primary recipe. Do not migrate it unless a subsequent detailed usage review identifies consumers; Ansible’s `lineinfile` is the likely functional replacement.

### Target Details

- **Operating System**: The Chef cookbook metadata declares Ubuntu 18.04+ and CentOS 7+ support. The Nginx configuration uses Debian/Ubuntu layout and identities (`www-data`, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`), UFW, `/var/log/auth.log`, and an `ssh` service name. Conversely, `Vagrantfile` selects `generic/fedora42`, while `vagrant-provision.sh` uses `apt-get`. The effective intended OS is therefore ambiguous; the source configuration most closely matches **Ubuntu/Debian**, but implementation must select and test a supported OS explicitly. Do not default blindly to RHEL 9 because the source includes Ubuntu-specific layout and tooling.
- **Virtual Machine Technology**: Vagrant using the Libvirt provider. The development guest is allocated 2 GB RAM and 2 vCPUs and connected through a private network plus forwarded 80/443 ports.
- **Cloud Platform**: Not specified. No cloud provider tooling, metadata endpoint use, or cloud-specific configuration was found.

## Migration Approach

Create a version-controlled Ansible project with a site playbook and independently testable roles such as `baseline_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Keep environment-specific sites, paths, domains, firewall policy, and certificate strategy out of role defaults where possible. Establish idempotence and check-mode support from the outset, and use handlers for Nginx, Fail2ban, sysctl, systemd daemon reload, Redis, PostgreSQL, and application restarts.

Coordinate ownership across platform/security/application teams: platform owns OS abstraction, packages, services, and inventories; security approves SSH, firewall, sysctl, Fail2ban, and certificate controls; application/database owners define the FastAPI revision, dependency lock policy, health check, database schema/migration process, and least-privilege database role. Require a parallel test environment before making changes that could terminate active SSH access.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Remove Chef bootstrap and Chef Solo execution. Use `ansible-core` from a pinned, supported execution environment and an inventory-driven `ansible-playbook` workflow.
- **Berkshelf and Chef Supermarket**: Retire cookbook resolution and vendoring. Pin Ansible collections in `requirements.yml` only where collections are actually needed; favor built-in modules such as `ansible.builtin.package`, `service`, `template`, `file`, `git`, `pip`, `systemd_service`, and `command`/`shell` only when no declarative module fits.
- **nginx cookbook 12.3.1**: Replace with an `nginx_multisite` role using OS-conditional package names/layout, Jinja2 templates, directory/file tasks, validation via `nginx -t`, and handlers. The current cookbook declares Nginx as a policy dependency but directly installs the `nginx` package rather than including the external cookbook; verify whether the Supermarket dependency is functionally needed before retaining any equivalent.
- **memcached cookbook 6.1.0**: Replace with direct installation, enablement, and configuration of the OS Memcached package. The reviewed local cookbook only includes `memcached` and has no explicit local settings, so define required configuration and network exposure with the cache/application owners.
- **redisio cookbook 7.2.4 and transitive selinux cookbook 6.2.4**: Replace with direct Redis package/service management or a vetted maintained Ansible role/collection. Implement Redis configuration declaratively rather than reproducing the Chef Ruby block that edits generated configuration. Decide whether SELinux configuration applies only to RHEL-family targets; it is locked transitively but not explicitly used by local source.
- **ssl_certificate cookbook 2.1.0**: It is resolved in `Policyfile.lock.json` and declared in `Policyfile.rb`, although it is commented out in `Berksfile` and the local cookbook generates certificates with OpenSSL directly. Replace development self-signed generation with `community.crypto` certificate/key tasks or, for production, an approved CA/ACME/certificate-management integration.
- **Python/FastAPI dependencies from the external Git repository**: The Chef code tracks the moving `main` branch and installs an unreviewed `requirements.txt`. Pin a commit/tag and Python dependencies or use an internal artifact/repository; define an approved deployment process and dependency vulnerability scanning.
- **PostgreSQL**: Replace shell `psql` statements with `community.postgresql` modules where feasible. The Ansible controller/execution environment will need the PostgreSQL Python driver, and database tasks require appropriate local/remote authentication.
- **OpenSSL, UFW, Fail2ban, systemd, sysctl, Git, Python, pip, and package repositories**: Model these as OS-family-specific dependencies. Package names, service names, log paths, SSH daemon configuration location, firewall implementation, and Nginx site layout differ materially between Ubuntu/Debian and Fedora/RHEL.

### Security Considerations

- **Hardcoded Redis password**: `cache::default` embeds `redis_secure_password_123` in Chef source. Move it to Ansible Vault or an external secrets manager, generate/rotate it, restrict Redis to localhost or trusted networks, use `no_log` for secret-bearing tasks, and ensure its configuration is not exposed in logs or backups.
- **Hardcoded PostgreSQL/application credentials**: `fastapi-tutorial::default` contains database user `fastapi`, password `fastapi_password`, and a plaintext `DATABASE_URL` written to `/opt/fastapi-tutorial/.env` with mode `0644`. Store the password/connection string in Vault or a secrets manager, create a least-privilege database role, change the environment file to service-user-readable only (normally `0600`), and avoid exposing it through facts, debug output, or CI logs.
- **TLS certificate and private key handling**: The source generates 2048-bit RSA self-signed certificates valid for 365 days and stores keys under `/etc/ssl/private` mode `0710`, with key files mode `0640` group `ssl-cert`. Preserve correct ownership/access without granting unnecessary Nginx access, use a managed production certificate source, define renewal/reload behavior, and verify certificate names/SANs. Self-signed certificates are appropriate only for development/testing.
- **Network and service exposure**: Nginx exposes 80/443 and FastAPI runs on `0.0.0.0:8000`; the source does not configure an Nginx upstream/proxy route to FastAPI, and the firewall only allows SSH/HTTP/HTTPS. Confirm intended FastAPI access and bind it to loopback when Nginx is its only ingress. Similarly, ensure Memcached and Redis are not internet-accessible.
- **SSH hardening safety**: The source disables root login and password authentication through `sed` edits to `sshd_config`, then restarts SSH. Use validated managed configuration/drop-ins, syntax validation, and a staged rollout with confirmed key-based access and console recovery to avoid lockout. Service and config names must be OS-specific (`ssh` vs `sshd`).
- **Host/network hardening**: Migrate UFW default deny plus SSH/HTTP/HTTPS exceptions, Fail2ban SSH/Nginx jails, `server_tokens off`, HTTP security headers, TLS protocol/cipher policy, and sysctl controls. Reassess the source’s blanket IPv6 disablement and ICMP echo suppression with networking/security owners; these can disrupt dual-stack services, monitoring, diagnostics, and platform policy.
- **Web header policy**: The Content-Security-Policy permits `'unsafe-inline'` for scripts and styles, and `X-XSS-Protection` is legacy. Retain compatibility only after application review; tighten CSP and modernize headers where feasible.
- **Supply-chain controls**: Chef bootstrap is fetched via `curl | bash`, Supermarket artifacts are remote, and application code follows a public Git branch. The Ansible solution should use signed/pinned packages, pinned Git commits/artifacts, controlled Galaxy collection sources, and dependency/image vulnerability scanning.

### Technical Challenges

- **OS and package-manager contradiction**: Fedora 42 is selected in Vagrant, while provisioning invokes APT and much of the Nginx/security configuration is Ubuntu-specific. Mitigation: make an explicit platform decision before role implementation; initially target Ubuntu/Debian for close behavioral parity, or redesign all paths, service accounts, firewall tooling, logs, SELinux handling, and package names for a RHEL/Fedora target. Maintain separate variable/task files only if multi-OS support is a real requirement.
- **Chef attribute precedence conflict**: Cookbook defaults use `/opt/server/{site}`, while `solo.json` overrides them to `/var/www/{site}`. Mitigation: define documented Ansible variable precedence and set each environment’s site map once in inventory/group variables; validate document roots and deployed content paths.
- **Imperative and fragile source operations**: Redis configuration is altered by a Ruby block that deletes lines after cookbook execution, and database creation relies on `|| true`, which suppresses both expected “already exists” and real errors. Mitigation: use declarative configuration templates/modules, explicit ownership/permissions, database modules, handlers, and meaningful failure conditions.
- **Application deployment is not fully specified**: The FastAPI code, requirements, runtime behavior, health endpoint, database schema initialization, and reverse-proxy relationship reside outside this repository or are absent. Mitigation: pin and inspect the application release, agree on systemd user/working-directory policy, add health checks and log strategy, and coordinate database migrations separately.
- **Current application runs as root**: The FastAPI systemd unit specifies `User=root`. Mitigation: provision a dedicated non-login service account, give it only required read/write permissions, and use systemd hardening options after application compatibility testing.
- **Nginx configuration portability and validation**: The templates assume Debian includes and `www-data`, duplicate TLS configuration at global and virtual-host scope, and set restrictive 1 KB client request limits that may break real requests. Mitigation: use OS-specific templates/layout or an Nginx role abstraction, run `nginx -t` before reload, and have application/security owners review payload limits and cipher/header policy.
- **Firewall/SSH changes can interrupt migration access**: Default deny and password-auth disablement risk blocking automation and administrators. Mitigation: pre-authorize Ansible control-node/management access, establish SSH keys and break-glass console access, and apply firewall/SSH changes last in a canary run.

### Migration Order

1. **Foundation and target-platform decision** (highest priority): Confirm Ubuntu/Debian versus Fedora/RHEL target, create inventories and variable conventions, establish an Ansible execution environment/CI linting, and build OS baseline/package abstraction. Recreate the Vagrant/Libvirt test target if it remains required.
2. **Baseline security controls**: Migrate and test SSH hardening, firewall, Fail2ban, sysctl, and required packages with a canary and recovery plan. Keep security role controls independently configurable and do not enable disruptive IPv6/ICMP settings without approval.
3. **Nginx multisite role**: Deploy Nginx configuration, static content, per-site document roots, site enablement, security headers, and validation/handlers. Implement development certificates initially only if needed for parity; integrate approved production certificate management before production use.
4. **Cache role**: Deploy Memcached and Redis with explicit bind/firewall policy and Vault-sourced Redis authentication. Replace the post-processing workaround with a tested Redis template or supported configuration mechanism.
5. **PostgreSQL and FastAPI application roles**: Provision PostgreSQL roles/database via idempotent modules, deploy a pinned application release and dependencies, protect environment secrets, run FastAPI as a non-root account, and validate systemd lifecycle and health checks.
6. **End-to-end integration and operational hardening**: Confirm application-to-PostgreSQL/cache connectivity, intended Nginx-to-FastAPI routing or direct exposure, TLS behavior, log collection, backups, certificate rotation, rollback, and CI-based idempotence/functional tests.

### Assumptions

- This plan treats the three directories under `cookbooks/` as the complete local Chef cookbook inventory because each contains `metadata.rb` and `recipes/default.rb`; no Puppet manifests, Salt states, or PowerShell modules appear in the supplied tree.
- The repository is intended primarily as a development/tutorial environment, based on self-signed certificates, tutorial application naming, Vagrant, and public Git `main` deployment. Production requirements have not been supplied.
- The desired authoritative operating system is not known. Although the Vagrant box is Fedora 42, the actual Chef content is predominantly Debian/Ubuntu-oriented and the bootstrap script cannot successfully use `apt-get` on a standard Fedora guest without additional changes.
- No cloud provider, production inventory, DNS automation, load balancer, container platform, monitoring platform, backup process, or CI pipeline is specified.
- Nginx serves the three included static sites. The source installs FastAPI on port 8000 but does not configure an Nginx upstream/proxy location; whether it should be externally reachable or proxied is undecided.
- The external FastAPI repository and its Python requirements are available at migration time. Its contents, license, database migration process, health endpoint, and supported Python/PostgreSQL versions were not reviewed here.
- The source’s resolved `ssl_certificate` and transitive `selinux` Chef dependencies may not correspond to active local behavior. Their actual necessity must be confirmed during detailed implementation.
- Existing passwords in source are considered insecure development placeholders and must be rotated rather than transferred unchanged.
- The provided static site content is non-sensitive example content; ownership and deployment workflow for future site assets have not been specified.
- Ansible controller access, target SSH key authentication, privilege escalation policy, secrets-manager choice, and team approval processes must be established before the security role is rolled out.
