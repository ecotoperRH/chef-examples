# MIGRATION FROM CHEF TO ANSIBLE

This repository is a small Chef Solo/Policyfile configuration consisting of three local cookbooks, provisioned in the order **nginx-multisite**, **cache**, then **fastapi-tutorial**. It builds a single-host development stack: hardened Nginx serving three TLS-enabled static sites, Redis and Memcached, and a FastAPI application backed by local PostgreSQL. The migration is moderate in implementation complexity despite the small cookbook count because package/service behavior is inconsistent across the declared Ubuntu/CentOS support and the supplied Fedora Vagrant image, and because several credentials and certificates are development-oriented and insecure for production.

A practical delivery estimate is **2–3 engineer-weeks** for role implementation, target-OS decisions, automated validation, and a Vagrant/libvirt smoke test; allow an additional week if production-grade certificate, secret, PostgreSQL lifecycle, and application-release requirements must be defined. Assign one engineer to the platform/security roles and one to application/data/cache roles, with a joint integration and cutover review.

## Module Migration Plan

This repository contains Chef cookbooks that need individual migration planning:

### MODULE INVENTORY

**CRITICAL PATH VERIFICATION:**
Only modules whose paths appear in the supplied repository tree are listed below.

- **nginx-multisite**:
  - Description: Installs and enables Nginx, renders the main and security configuration, creates static document roots and per-site index pages, and configures three named virtual hosts: `test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`. It also generates one self-signed TLS certificate/key pair per enabled site, removes the default Nginx site, and applies host security controls.
  - Path: `cookbooks/nginx-multisite`
  - Technology: Chef
  - Key Features: Nginx service management; TLS virtual hosts; static assets for test/CI/status sites; Fail2ban; UFW default-deny firewall with SSH/HTTP/HTTPS exceptions; sysctl security settings; SSH root-login and password-authentication disabling.

- **cache**:
  - Description: Configures Memcached through an external Chef cookbook and a Redis instance on port 6379 through `redisio`; establishes a Redis log directory, sets Redis authentication, enables Redis, and uses a Ruby block to remove several replica-related directives from the generated Redis configuration.
  - Path: `cookbooks/cache`
  - Technology: Chef
  - Key Features: Memcached inclusion; Redis password authentication; Redis service enablement; post-generation Redis configuration workaround.

- **fastapi-tutorial**:
  - Description: Deploys the FastAPI tutorial application from the public `dibanez/fastapi_tutorial` GitHub repository, installs Python and PostgreSQL packages, creates a Python virtual environment, installs application requirements, provisions a local PostgreSQL database/user, writes an application `.env`, and manages a systemd Uvicorn service on port 8000.
  - Path: `cookbooks/fastapi-tutorial`
  - Technology: Chef
  - Key Features: Git-based application deployment pinned only to branch `main`; Python venv/pip dependency installation; local PostgreSQL provisioning; systemd service running Uvicorn as `root`.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and Supermarket constraints. It comments out `ssl_certificate`, although the Policyfile still resolves it; reconcile this dependency discrepancy before retirement of Chef tooling.
- `Policyfile.rb`: Defines the canonical Chef run list and requests local cookbooks plus Nginx, Memcached, RedisIO, and SSL Certificate cookbook versions. Use its run order as the initial Ansible play/role sequencing baseline.
- `Policyfile.lock.json`: Locks the evaluated dependency set: Memcached 6.1.0, Nginx 12.3.1, RedisIO 7.2.4, SELinux 6.2.4 (transitive from RedisIO), and SSL Certificate 2.1.0. It also records that the local working tree was not clean when locked; validate actual desired state rather than treating this lock as a production baseline.
- `solo.rb`: Chef Solo configuration with cookbook paths under `/chef-repo`; superseded by an Ansible project layout, inventory, and `ansible.cfg`.
- `solo.json`: Chef Solo run list and runtime overrides for Nginx sites, SSL paths, and security controls. Convert it into version-controlled Ansible role defaults plus environment-specific `group_vars`; document precedence versus cookbook attributes.
- `Vagrantfile`: Development VM definition using `generic/fedora42`, private IP `192.168.121.10`, HTTP/HTTPS forwarded ports, rsync synchronization, and the libvirt provider (2 GB RAM, 2 CPUs). Retain or replace with an Ansible-driven test fixture.
- `vagrant-provision.sh`: Bootstrap script that uses `apt-get`, installs Chef from Omnitruck, installs Berkshelf, vendors cookbooks, and runs Chef Solo. It is both Chef-specific and incompatible with the declared Fedora Vagrant box; replace with Ansible installation/bootstrap and platform-correct package preparation.
- `cookbooks/nginx-multisite/attributes/default.rb`: Default site, certificate-path, and security values. Merge deliberately with the conflicting runtime document-root values in `solo.json`.
- `cookbooks/nginx-multisite/templates/`: ERB templates for Nginx, virtual hosts, Fail2ban, Nginx security settings, and sysctl settings. Translate these to Jinja2 templates and validate rendered configuration syntax and effective security behavior.
- `cookbooks/nginx-multisite/resources/lineinfile.rb`: Custom Chef resource present in the cookbook. Its use was not established by the reviewed primary recipe; inventory its consumers before cookbook removal and map any usage to `ansible.builtin.lineinfile`.
- `cookbooks/nginx-multisite/files/default/`: Static `index.html` content for the three served sites; migrate as role files or deploy from the application/content pipeline.

### Target Details

- **Operating System**: The local cookbook metadata declares Ubuntu 18.04+ and CentOS 7.0+ support. However, the Vagrant target is `generic/fedora42`, while the provisioning script, `ufw`, `www-data`, Debian-style Nginx `sites-available/sites-enabled`, and `apt-get` are Ubuntu/Debian-oriented. The source does not define one valid target platform. Select and test a supported OS explicitly before migration; Ubuntu LTS is the closest fit to the current resource paths and commands. Do not default to RHEL 9 because the source contains meaningful Debian-specific assumptions.
- **Virtual Machine Technology**: Vagrant with the libvirt provider; therefore the development VM is KVM/libvirt-oriented. No production virtualization platform is specified.
- **Cloud Platform**: Not specified; no cloud-provider configuration was identified.

## Migration Approach

Create an Ansible repository with an inventory and environment-specific variables, a top-level playbook, and independently testable roles such as `base_security`, `nginx_multisite`, `cache`, `postgresql`, and `fastapi_tutorial`. Preserve Chef ordering initially: baseline security/Nginx prerequisites, Nginx/TLS/site configuration, caches, PostgreSQL, then application deployment. Use handlers for Nginx, Fail2ban, SSH, sysctl, PostgreSQL, and systemd reloads rather than arbitrary imperative commands. Add Molecule or equivalent Vagrant/libvirt integration tests, `nginx -t`, service health checks, HTTP(S) probes for every virtual host, Redis authentication checks, and a FastAPI endpoint check.

Coordinate the work through a shared variable contract: site map, TLS source and paths, firewall policy, Redis secret reference, PostgreSQL database/user ownership, Git release reference, and FastAPI environment variables. Require platform and security owners to approve this contract before roles are integrated. Run Chef and Ansible only in a disposable validation VM during parity testing; use phased rollout and rollback procedures for any shared or production host.

### Key Dependencies to Address

- **Chef Infra Client/Solo, Berkshelf, and Policyfiles**: Replace with Ansible Core, a documented collection/role `requirements.yml` if third-party Ansible content is adopted, inventories, playbooks, and group variables. Chef’s run list becomes explicit play and role ordering.
- **nginx Chef cookbook (locked 12.3.1)**: The local Nginx recipe installs the OS `nginx` package directly rather than including this cookbook. Use `ansible.builtin.package`, templating, service handlers, and OS-specific variable files; remove the unused dependency unless another unreviewed consumer requires it.
- **memcached Chef cookbook (locked 6.1.0)**: Replace with OS package installation, configuration templating only if required after capturing the effective Chef-managed configuration, and service enable/start tasks.
- **redisio Chef cookbook (locked 7.2.4)**: Replace with OS Redis packages, a managed Redis configuration, directory permissions, service management, and explicit configuration validation. Model the source’s removed replica settings only after confirming why the workaround was necessary.
- **SELinux Chef cookbook (locked 6.2.4, transitive)**: It reflects the RedisIO dependency lock, but the visible local recipes are primarily Debian-oriented. Decide whether SELinux enforcement and port/file-context management are in scope for a RHEL/Fedora target; otherwise remove this Chef-era transitive dependency.
- **ssl_certificate Chef cookbook (locked 2.1.0)**: Policyfile locks it but visible local code generates certificates with OpenSSL and Berksfile comments it out. Replace development self-signed generation with `community.crypto` tasks or, preferably, a managed CA/ACME/certificate delivery process. Eliminate the stale Chef dependency after confirmation.
- **GitHub application repository and Python requirements**: Replace Chef `git`/shell execution with `ansible.builtin.git`, preferably pinning an immutable commit or release tag, plus `ansible.builtin.pip` using the venv. Define package mirror, outbound access, and supply-chain controls.
- **PostgreSQL tooling**: Use `community.postgresql` database/user modules with a correctly scoped PostgreSQL administrative connection rather than `psql ... || true` shell commands. Install the required collection and Python database driver for the chosen target.
- **OpenSSL, Fail2ban, UFW, and sysctl**: Manage through packages and native Ansible modules/templates. If choosing RHEL/Fedora, replace UFW behavior with firewalld and verify service names, users/groups, paths, and SELinux labels.

### Security Considerations

- **Hardcoded Redis credential (`cache`)**: `redis_secure_password_123` is embedded in the recipe. Store a replacement secret in Ansible Vault or an approved external secret manager, set restrictive configuration permissions, rotate it, and avoid exposing it in logs.
- **Hardcoded PostgreSQL/application credential (`fastapi-tutorial`)**: The database password `fastapi_password` appears in SQL commands and the generated `.env`/DATABASE_URL. Replace it with a generated or managed secret; render `.env` with restrictive ownership and mode (not the current world-readable `0644`), and rotate the database account during cutover.
- **TLS private keys (`nginx-multisite`)**: The current code creates 2048-bit RSA self-signed certificates valid for 365 days under `/etc/ssl/private` with group `ssl-cert` and mode `0640`. Development-only self-signed issuance causes browser warnings and has no rotation process. Use organization-issued certificates or ACME in production; protect key material with Ansible Vault/external secret delivery and preserve least-privilege file access.
- **SSH hardening (`nginx-multisite`)**: Root login and password authentication are disabled through `sed` edits to `sshd_config`. Use a validated drop-in or managed configuration with an SSH syntax check and ensure a tested key-based administrative path exists before applying; retain a console/rollback path to prevent lockout.
- **Firewall and intrusion prevention (`nginx-multisite`)**: The source applies default-deny UFW policy and opens SSH, HTTP, and HTTPS, while enabling Fail2ban. Encode rules idempotently with the selected platform firewall module, explicitly define permitted management networks if required, and test ordering to avoid lockout.
- **Application privilege (`fastapi-tutorial`)**: Uvicorn runs as `root`, increasing impact of application compromise. Create a dedicated non-login service user, grant only required files/directories, and use systemd hardening controls where compatible.
- **Public, unpinned application source (`fastapi-tutorial`)**: The deployment follows Git branch `main` and installs whatever is in `requirements.txt`. Pin a reviewed commit/tag and dependency hashes or locked versions; use controlled artifact/repository access.
- **Visible certificate subject email and maintainer email**: `admin@example.com` appears as placeholder metadata and in certificate subjects. Replace with approved organizational identity data if certificates continue to be generated.
- **Secret inventory by module**: `nginx-multisite` handles TLS private keys and self-signed certificate subjects; `cache` contains a hardcoded Redis password; `fastapi-tutorial` contains a hardcoded PostgreSQL password and embeds it in `.env`. No Chef encrypted data bags or Chef Vault use was visible in the reviewed dependency and entrypoint files.

### Technical Challenges

- **Platform contradiction**: Fedora 42/libvirt is declared, yet bootstrap and configuration use Apt, UFW, `www-data`, Debian Nginx layout, and `ssh` service naming. Mitigation: choose Ubuntu LTS or implement and test distinct Debian and Red Hat variable/task paths; do not claim multi-platform support without CI coverage.
- **Conflicting site document roots**: Cookbook attributes specify `/opt/server/{test,ci,status}`, whereas `solo.json` overrides them to `/var/www/<hostname>`. Mitigation: make the site dictionary a single Ansible variable source per environment and establish which paths contain the intended content before cutover.
- **Chef external-cookbook behavior is partly opaque**: Memcached and Redis behavior is inherited from Supermarket cookbooks, and the Redis recipe applies a post-render Ruby text-removal workaround. Mitigation: capture effective package versions, Redis configuration, and service state from a known-good Chef host, then implement desired configuration explicitly in Ansible.
- **Imperative/non-idempotent database setup**: SQL uses `|| true`, masking failures and making state verification weak. Mitigation: use PostgreSQL Ansible modules, validate authentication and ownership, and make schema/application migrations a separate controlled release concern.
- **Nginx configuration and template parity**: Main configuration, security headers/settings, virtual hosts, and TLS references are spread across recipes and templates. Mitigation: translate templates as a tested role, run `nginx -t` before reload, and verify all three HTTP/HTTPS sites and expected redirects/headers.
- **Service lifecycle ordering**: FastAPI requires network and PostgreSQL, while Nginx may later proxy it depending on template content not reviewed in this high-level survey. Mitigation: define explicit systemd dependencies and acceptance tests; confirm the Nginx site template’s upstream behavior during implementation.
- **Development-only certificate and network assumptions**: Private IP/forwarded port values and self-signed TLS are suited to Vagrant, not necessarily deployment. Mitigation: separate developer, test, and production inventories and avoid promoting Vagrant addresses/certificates into production variables.

### Migration Order

1. **Foundation and security baseline**: Decide target OS and inventory model; create common package/service abstraction, firewall, SSH hardening, sysctl, and Fail2ban role. Validate console/key access and firewall rules in an isolated VM.
2. **Nginx multisite role**: Translate static content, templates, virtual-host map, Nginx service handlers, and certificate strategy. Validate rendered configuration and all three sites on the chosen platform.
3. **Cache role**: Implement Memcached and Redis explicitly, introduce vaulted Redis credentials, and validate Redis configuration/service behavior including the Chef-era replica-setting workaround.
4. **PostgreSQL and FastAPI application roles**: Provision the database/user with vaulted credentials, deploy a pinned application revision into a venv, use a non-root systemd identity, and validate application health. Integrate it with Nginx only after confirming the intended upstream/proxy behavior.
5. **Integrated acceptance and Chef decommission**: Compare effective package, service, firewall, TLS, site, cache, database, and application state on disposable Vagrant/libvirt hosts; execute staged rollout, retain tested rollback, then remove Chef bootstrap, Solo, Berkshelf, and Policyfile workflows.

### Assumptions

- The three directories under `cookbooks/` are the complete set of local Chef cookbooks in scope; no Puppet, Salt, or PowerShell modules appear in the supplied tree.
- Chef Solo is the active execution path because `vagrant-provision.sh`, `solo.rb`, and `solo.json` implement it; the Policyfile is treated as dependency/run-list documentation unless an external Chef workflow uses it.
- This is intended as a single-node development/demo stack because PostgreSQL, caches, Nginx, and FastAPI are configured locally; high availability, external databases, and container orchestration are not defined.
- Ubuntu LTS is recommended only as the closest behavioral match, not as a confirmed production target. Fedora 42 in Vagrant conflicts with the provisioning script and must be resolved by stakeholders.
- The exact Nginx security directives, Fail2ban jail contents, sysctl values, and virtual-host proxy behavior need implementation-time verification from the templates; this survey did not perform a template-by-template audit.
- The FastAPI repository’s application schema, required environment variables beyond `DATABASE_URL`, dependency lock status, and health endpoint are not specified in the reviewed cookbook.
- No production DNS, certificate authority, cloud provider, VM platform beyond development libvirt, CI/CD system, monitoring, backup, or restore requirements are defined.
- The externally locked `ssl_certificate` dependency may be stale because it is commented in `Berksfile` and not visibly included by local recipes; confirm before deciding whether it has any runtime effect.
- The displayed hardcoded passwords and self-signed certificates are assumed to be development values, but they must be treated as exposed credentials and rotated rather than copied into Ansible.
