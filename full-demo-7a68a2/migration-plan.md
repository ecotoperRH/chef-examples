# MIGRATION FROM CHEF TO ANSIBLE

This repository is a Chef Solo/Policyfile configuration consisting of three local cookbooks: an Nginx multi-site edge host, a Redis/Memcached cache layer, and a FastAPI tutorial application backed by a local PostgreSQL instance. Provisioning is intended for a Vagrant/libvirt development VM, although the declared VM image and the provisioning script are inconsistent. The migration is moderate in scope: the cookbook count is small, but the implementation includes operating-system-specific package/service behavior, TLS lifecycle, firewall/SSH hardening, externally sourced application code, and database credentials. A two-person team can reasonably deliver a tested initial Ansible implementation in approximately 2–3 weeks, followed by environment-specific hardening and acceptance testing.

The recommended target is an Ansible repository organized as composable roles (`nginx_multisite`, `cache`, `fastapi_tutorial`) with environment inventory/group variables, Ansible Vault-encrypted secrets, and separate development versus production TLS and firewall policies. Preserve functional parity first, then replace the development-only and imperative workarounds identified below.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

- **cache**:
  - Description: Installs and enables Memcached and Redis caching services. Configures Redis on port 6379, creates its log directory, enables Redis, and applies an imperative cleanup to remove several replication-related settings from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached cookbook inclusion; Redis authentication configuration; Redis log directory ownership; Redis enablement; post-generation Redis configuration workaround.

- **fastapi-tutorial**:
  - Description: Deploys the `dibanez/fastapi_tutorial` application from Git into `/opt/fastapi-tutorial`, creates a Python virtual environment, installs application requirements, provisions a local PostgreSQL database and user, writes an application `.env`, and manages a Uvicorn systemd service listening on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Python 3/Pip/venv and PostgreSQL packages; Git checkout of the `main` branch; local database provisioning; systemd service lifecycle; environment-file based database connection configuration.

- **nginx-multisite**:
  - Description: Configures Nginx to serve three static, SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), deploys site content, configures Nginx security directives, provisions self-signed TLS certificates, and applies host hardening through Fail2ban, UFW, sysctl, and SSH settings.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx configuration and site templates; static site files; HTTPS virtual hosts and self-signed certificates; Fail2ban; default-deny UFW policy with SSH/HTTP/HTTPS exceptions; SSH root-login and password-authentication disablement; kernel security sysctl configuration; custom `lineinfile` Chef resource present for source review during detailed migration.

**CRITICAL PATH VERIFICATION:** All module paths above are present in the supplied repository tree, and each cookbook's `recipes/default.rb` was reviewed before inclusion.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and external Nginx, Memcached, and Redis dependencies. It is replaced by Ansible collection/role requirements only where community content is deliberately adopted; native roles are preferable for this small configuration.
- `Policyfile.rb`: Defines the authoritative Chef run list and dependency constraints. Translate the run order to a playbook role order: Nginx/security, cache, then FastAPI, while correcting service dependency ordering as needed.
- `Policyfile.lock.json`: Locks resolved Chef dependencies: Memcached 6.1.0, Nginx 12.3.1, RedisIO 7.2.4, SELinux 6.2.4 (transitive), and SSL Certificate 2.1.0. Use it as the dependency baseline; do not attempt to carry Chef cookbook versions directly into Ansible.
- `solo.rb`: Chef Solo paths and logging configuration. Replace with standard Ansible inventory, `ansible.cfg`, playbooks, and role paths; no Chef client/solo runtime is needed after cutover.
- `solo.json`: Chef node attributes defining the three sites, TLS directory paths, and security switches. Convert this into environment-specific `group_vars`/`host_vars`, with secrets removed to Vault.
- `Vagrantfile`: Development VM definition using `generic/fedora42`, private IP `192.168.121.10`, forwarded HTTP/HTTPS ports, and the libvirt provider (2 GB RAM, 2 CPUs). Retain or replace it as a development test harness; update provisioning to invoke `ansible_local` or `ansible-playbook`.
- `vagrant-provision.sh`: Installs Chef and Berkshelf, vendors cookbooks, and runs Chef Solo. It uses `apt-get`, which conflicts with the Fedora Vagrant box; replace entirely with an OS-consistent Ansible bootstrap/provisioning workflow.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, TLS, and host-security values. Migrate into role defaults and environment variables, with production values separated from development defaults.
- `cookbooks/nginx-multisite/templates/`: Nginx, per-site, security, Fail2ban, and sysctl templates. Convert to Jinja2 templates after rendering/semantic comparison against Chef output.
- `cookbooks/nginx-multisite/files/default/`: Static index pages for the test, CI, and status virtual hosts. Migrate with `ansible.builtin.copy` or a static-content deployment mechanism.

### Target Details

- **Operating System**: The cookbook metadata declares Ubuntu 18.04+ and CentOS 7.0+ support. The source assumes Debian/Ubuntu conventions in several places: `apt-get`, UFW, `/etc/nginx/sites-available`, `/etc/nginx/sites-enabled`, `www-data`, and an `ssh` service name. Conversely, the Vagrant box is `generic/fedora42`, and the Policyfile pulls a transitive SELinux cookbook. This is not a deployable single OS target as written. Treat Ubuntu/Debian as the closest match to the active recipes unless the team explicitly standardizes on a RHEL-family platform; implement and test platform-specific variables/tasks if both are required.
- **Virtual Machine Technology**: Vagrant with the libvirt provider. The defined test VM has a private network at `192.168.121.10` and forwarded host ports 8080/8443.
- **Cloud Platform**: Not specified. No cloud-provider tooling or metadata integration was found.

## Migration Approach

Create an Ansible inventory for development and future environments, then implement one role per local cookbook. Use role defaults for non-sensitive configuration, group variables for site/application topology, Vault for credentials and private data, handlers for Nginx/Fail2ban/SSH/systemd reloads, and check-mode/idempotence tests. Pin the FastAPI application to an immutable Git tag or commit rather than the moving `main` branch before production adoption.

### Key Dependencies to Address

- **Chef Infra Client / Chef Solo (>= 16.0)**: Retire Chef bootstrap, Solo configuration, Berkshelf vendoring, and Policyfile execution. Use a version-controlled Ansible project executed from CI or an approved control node.
- **Chef Supermarket `memcached` (locked 6.1.0)**: Replace with native Ansible package and service tasks (`memcached` package/service), with explicit configuration only if the current cookbook rendered non-default settings that must be retained.
- **Chef Supermarket `redisio` (locked 7.2.4)**: Replace with OS packages and managed Redis configuration/template tasks. Define `requirepass` through Ansible Vault, manage `/var/log/redis` ownership, and remove the Chef `ruby_block` workaround by generating a valid Redis configuration directly. Validate Redis version/configuration compatibility before retaining or intentionally omitting replication directives.
- **Chef Supermarket `nginx` (locked 12.3.1)**: Replace with `ansible.builtin.package`, `template`, `file`, and `service`/`systemd` tasks, or a consciously selected, pinned Ansible collection role. The current local cookbook installs Nginx directly rather than visibly including this dependency, so establish which generated/default behavior is actually required during parity testing.
- **Chef Supermarket `ssl_certificate` (locked 2.1.0)**: The local cookbook generates certificates with OpenSSL rather than using this cookbook. Use `community.crypto` for development self-signed certificates or integrate the organization's CA/ACME process for production. Declare the chosen collection in `collections/requirements.yml`.
- **Chef Supermarket `selinux` (locked 6.2.4, transitive from RedisIO)**: Needed only if RHEL-family systems are supported. Use `ansible.posix.selinux` and appropriate file-context/port/firewall tasks after selecting the target OS; it is not applicable to Ubuntu/UFW-only deployment.
- **PostgreSQL and Python application dependencies**: Replace shell provisioning with `community.postgresql` database/user modules and an Ansible-managed Python virtual environment. The database modules require a suitable PostgreSQL driver on the managed node/control context; plan it explicitly.
- **GitHub source `https://github.com/dibanez/fastapi_tutorial.git`**: Maintain network access and source provenance, pin a revision, and decide whether deployment should clone directly from GitHub or consume an internally built/versioned artifact.
- **Vagrant/libvirt**: Keep only for local integration testing. Replace the Chef shell provisioner with Ansible provisioning and make VM OS selection consistent with role support.

### Security Considerations

- **Hardcoded Redis password**: `cache::default` contains `redis_secure_password_123` as a Redis `requirepass`. Remove it from source control, rotate it, store its replacement in Ansible Vault or an external secret manager, and set restrictive ownership/mode on Redis configuration.
- **Hardcoded PostgreSQL/FastAPI credentials**: `fastapi-tutorial::default` embeds the `fastapi` password in SQL and writes it into `/opt/fastapi-tutorial/.env`, currently mode `0644`. Generate or provision a Vault-backed credential, use `community.postgresql.postgresql_user`, restrict the environment file to the service account (normally `0600`), and avoid logging database URLs.
- **TLS certificate management**: Nginx sites use automatically generated, 365-day, RSA-2048 self-signed certificates. Keep this only for development. Production requires CA-issued certificates, renewal automation, secure private-key storage, and least-privilege Nginx access. The existing key directory is group-restricted (`root:ssl-cert`, `0710`) and key files are mode `0640`; preserve or strengthen these controls while confirming the Nginx worker/service account can read keys as needed.
- **Network exposure and firewall**: The FastAPI Uvicorn service binds to `0.0.0.0:8000`, while UFW opens only SSH, HTTP, and HTTPS. Confirm whether port 8000 must be private/reverse-proxied only. Implement firewall rules using the selected OS firewall framework (UFW for Ubuntu or firewalld for RHEL), avoiding accidental administrative lockout.
- **SSH hardening**: The source disables root SSH login and password authentication via `sed`. Use a validated `sshd_config` drop-in/template, check configuration with `sshd -t`, retain break-glass/key-based access, and restart the correct service name for the OS only after validation.
- **Fail2ban and kernel hardening**: Preserve the reviewed Fail2ban and sysctl templates only after security review and OS compatibility verification. Apply sysctl settings through managed files and reload handlers rather than opaque shell commands.
- **Service privileges**: The FastAPI systemd service runs as `root`. Migrate initially only if required for parity, but prioritize a dedicated, non-login application account with ownership limited to application runtime paths.
- **Supply-chain controls**: The application tracks Git `main` and Pip dependencies are installed without shown hashes/lock enforcement. Pin the application commit and dependency artifacts, use trusted package repositories, and perform dependency/vulnerability review before production migration.
- **Credential patterns by module**:
  - `cache`: Hardcoded Redis authentication password in recipe configuration.
  - `fastapi-tutorial`: Hardcoded PostgreSQL user password and plaintext `DATABASE_URL` in `.env`.
  - `nginx-multisite`: Generated private TLS keys and self-signed certificates; no externally supplied secret was found in the reviewed files.

### Technical Challenges

- **Conflicting platform assumptions**: Fedora 42/libvirt is declared for Vagrant, but provisioning uses APT/UFW/Debian Nginx layout and metadata lists Ubuntu/CentOS. Select and document a supported OS matrix before writing reusable roles. Mitigate with an Ubuntu-first baseline or explicit Debian/RHEL task branches tested in CI.
- **Recipe ordering versus service dependencies**: Policy order runs Nginx before FastAPI, though an eventual proxy configuration may depend on the application being ready. The currently reviewed site configuration is static-content-oriented. Validate rendered Nginx templates and required upstream behavior before defining final role ordering and health checks.
- **Imperative/non-idempotent Chef workarounds**: Redis configuration is edited after cookbook rendering with a Ruby block, PostgreSQL DDL relies on `psql ... || true`, and SSH is modified with `sed`. Replace these with declarative Ansible modules/templates and idempotent database/configuration checks.
- **Configuration source precedence**: Nginx site document roots differ between cookbook defaults (`/opt/server/...`) and `solo.json` (`/var/www/<site>`). Establish an authoritative variable model and expected rendered configuration per environment before cutover.
- **Package/service layout portability**: `www-data`, `ssh`, UFW, Nginx sites-enabled, and PostgreSQL service/package names are distribution-specific. Parameterize them or limit the initial migration to one validated distribution.
- **Application reproducibility and runtime readiness**: A direct Git clone from a mutable branch plus unrestricted Pip install does not produce a reproducible deployment. Add revision pinning, dependency lock controls, service health checks, and rollback capability.
- **Template parity**: Nginx, security, Fail2ban, and sysctl behavior resides in Chef ERB templates. Convert them to Jinja2 and compare generated output/configuration validation (`nginx -t`, `sshd -t`, service status) before replacing Chef.

### Migration Order

1. **Foundation and target standardization**: Agree on Ubuntu/Debian versus RHEL-family target, correct or replace the Vagrant test image/provisioning, establish inventories, Ansible version/collection requirements, Vault/secrets process, CI linting, and a baseline verification host.
2. **cache**: Implement Memcached and Redis as independent, declarative services; move and rotate Redis credentials; validate client connectivity and Redis configuration without the Chef post-processing hack.
3. **fastapi-tutorial**: Implement OS packages, a dedicated service identity, source/artifact deployment, Python virtual environment, Vault-backed PostgreSQL provisioning, environment file permissions, and systemd service/health validation. Complete this before adding any application proxy integration.
4. **nginx-multisite**: Migrate host security controls, Nginx base/security templates, static sites, virtual hosts, and development TLS. Validate firewall/SSH changes through console access and test Nginx configuration before handler reloads. Introduce production CA/ACME integration as a separately reviewed security milestone.
5. **Integrated validation and Chef retirement**: Test Vagrant/libvirt deployment and selected production-like hosts; verify HTTP/HTTPS virtual hosts, cache services, database/application startup, firewall policy, SSH access, certificate behavior, and idempotent repeat runs. Run Chef and Ansible in a controlled comparison period, then decommission Chef Solo/Berkshelf artifacts.

### Assumptions

- The supplied tree contains no Puppet, Salt, or PowerShell modules; Chef is the only infrastructure-as-code technology identified.
- Each directory under `cookbooks/` with `metadata.rb` and `recipes/default.rb` is treated as an independent Chef cookbook: `cache`, `fastapi-tutorial`, and `nginx-multisite`.
- Ubuntu/Debian is the most compatible initial Ansible target because active recipes and the provisioning script use APT, UFW, `www-data`, and the Debian Nginx site layout. This remains an assumption because Vagrant explicitly selects Fedora 42 and cookbook metadata also claims CentOS support.
- No production cloud provider, orchestration platform, DNS management, load balancer, or external secret manager is specified in the reviewed configuration.
- Self-signed certificates, local PostgreSQL, local Redis, and local Memcached appear to be development/tutorial choices; production topology and certificate authority requirements must be confirmed.
- The reviewed Nginx cookbook's default recipe calls security, Nginx, SSL, and sites sub-recipes. Detailed implementation must inspect/render all source templates and the custom `resources/lineinfile.rb` only if it is used by the final desired behavior.
- `ssl_certificate` is present in `Policyfile.rb` and the lockfile but commented out in `Berksfile`; the local SSL recipe uses OpenSSL directly. Its intended runtime relevance requires confirmation.
- The direct Git repository, its `main` revision, and Python requirements are reachable and suitable for the intended deployment; version pinning and internal artifact policies have not been supplied.
- The Vagrant provisioning script reports a different IP (`192.168.56.10`) than the Vagrantfile (`192.168.121.10`); use the Vagrantfile or a newly defined inventory as the authoritative test address after team confirmation.
- Timeline estimate assumes one target OS, available package repositories/Git access, and no undocumented production requirements. Supporting both Debian and RHEL families, integrating an enterprise PKI/secret manager, or changing the application deployment model will extend the estimate.
