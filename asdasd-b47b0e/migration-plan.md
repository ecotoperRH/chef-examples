# MIGRATION FROM CHEF TO ANSIBLE

## Executive Summary

This repository is a Chef Solo/Policyfile project with exactly three local Chef cookbooks and several external cookbook dependencies. The migration scope covers Nginx multisite hosting, host security, Redis/Memcached, PostgreSQL, and a FastAPI application running in a Vagrant/libvirt development VM. The migration is moderate overall, with higher risk around OS inconsistency, hardcoded credentials, TLS key handling, firewall/SSH changes, and non-idempotent database shell commands. A two-to-four-week effort for one engineer is a reasonable estimate for implementation, testing, security remediation, and documentation.

## Module Migration Plan

This repository contains Chef cookbooks that require separate Ansible migration planning.

### MODULE INVENTORY

The following three entries are the complete local cookbook inventory. Each path is a directory shown in the repository tree and contains `recipes/default.rb` and `metadata.rb`.

- **cache**
  - **Description:** Configures the host caching services by including Memcached and Redis, setting Redis to listen on port 6379 with authentication, creating the Redis log directory, enabling Redis, and applying a Redis configuration cleanup workaround.
  - **Path:** `cookbooks/cache`
  - **Technology:** Chef cookbook
  - **Key Features:** Memcached integration, RedisIO integration, Redis authentication, Redis log directory ownership, service enablement, and Ruby-based post-configuration editing.
  - **Migration Complexity:** Moderate. Package and service management are straightforward, but the password must be vaulted and the configuration workaround must become declarative and idempotent.

- **fastapi-tutorial**
  - **Description:** Installs the Python and PostgreSQL runtime for a FastAPI tutorial application, clones the application source, creates a Python virtual environment, installs Python requirements, creates the PostgreSQL database and user, writes application environment configuration, and runs Uvicorn through systemd.
  - **Path:** `cookbooks/fastapi-tutorial`
  - **Technology:** Chef cookbook
  - **Key Features:** Python 3/pip/venv packages, Git checkout of `https://github.com/dibanez/fastapi_tutorial.git` at `main`, PostgreSQL service management, database bootstrap, `.env` generation, and a systemd service listening on port 8000.
  - **Migration Complexity:** Moderate to high. Application deployment, database provisioning, systemd management, remote source pinning, and credentials are currently combined in one recipe.

- **nginx-multisite**
  - **Description:** Installs and configures Nginx for three SSL-enabled virtual hosts (`test.cluster.local`, `ci.cluster.local`, and `status.cluster.local`), serves per-site static content, and applies host security controls.
  - **Path:** `cookbooks/nginx-multisite`
  - **Technology:** Chef cookbook
  - **Key Features:** Nginx package/service management, templated Nginx and security configuration, site document roots, virtual-host templates and symlinks, Fail2ban, UFW default-deny firewall rules, SSH hardening, sysctl settings, and development self-signed certificates.
  - **Internal Recipes:** `default`, `nginx`, `security`, `sites`, and `ssl`.
  - **Migration Complexity:** High relative to the repository because it combines web serving, templates, certificates, firewall policy, SSH policy, sysctl settings, and service reload notifications.

**External cookbooks are dependencies, not additional local modules:** `nginx`, `memcached`, `redisio`, `selinux`, and `ssl_certificate` are resolved from Chef Supermarket and therefore are not listed as local MODULE INVENTORY entries.

### Infrastructure Files

- `Berksfile`: Defines the Chef Supermarket source, local cookbook paths, and external constraints for `nginx ~> 12.0`, `memcached ~> 6.0`, and `redisio ~> 7.2.4`. The `ssl_certificate` declaration is commented out here.
- `Policyfile.rb`: Defines policy `nginx-multisite-policy`, the run list for all three local cookbooks, and external cookbook constraints including `ssl_certificate ~> 2.1`.
- `Policyfile.lock.json`: Locks `nginx 12.3.1`, `memcached 6.1.0`, `redisio 7.2.4`, `selinux 6.2.4`, and `ssl_certificate 2.1.0`; it also records that `cache` depends on Memcached and RedisIO, and RedisIO depends on SELinux.
- `Vagrantfile`: Defines the `generic/fedora42` Vagrant box, libvirt provider, 2 GB RAM, 2 CPUs, private IP `192.168.121.10`, and forwarded HTTP/HTTPS ports 8080/8443. It uses rsync and invokes `vagrant-provision.sh`.
- `vagrant-provision.sh`: Uses `apt-get`, installs Chef and Berkshelf, vendors dependencies, and runs Chef Solo. It should be replaced by Ansible provisioning or retained only as a transitional test wrapper.
- `solo.rb`: Defines Chef Solo cache, cookbook paths, and logging. Its Ansible equivalent is primarily project/inventory structure and logging conventions.
- `solo.json`: Supplies the run list, three Nginx site definitions, SSL paths, and security settings. Migrate these values to inventory/group variables, role defaults, and Ansible Vault as appropriate.
- `project-plan.md`: Describes the broader X2Ansible migration tool and workflow; it is project context rather than target-host runtime configuration.

### Target Details

- **Operating System:** Ambiguous. Vagrant explicitly selects Fedora 42, while `vagrant-provision.sh` uses Debian/Ubuntu `apt-get` and UFW commands. Cookbook metadata declares Ubuntu >= 18.04 and CentOS >= 7. The migration must select and test one supported OS. If Fedora 42 remains the target, use Fedora package names and firewalld/SELinux conventions; alternatively change the development box to Ubuntu for closer parity with the existing bootstrap.
- **Virtual Machine Technology:** Vagrant using libvirt. The VM has 2 CPUs, 2 GB RAM, private networking, and forwarded ports.
- **Cloud Platform:** Not specified; no AWS, Azure, or GCP configuration is present.

## Migration Approach

Create an Ansible project with an inventory for the Vagrant VM and roles such as `host_security`, `cache`, `fastapi_tutorial`, and `nginx_multisite`. Convert Chef templates to Jinja2 templates, Chef notifications to handlers, recipe inclusion to explicit play or role ordering, and shell/Ruby workarounds to native Ansible modules where possible. Keep secrets outside ordinary variables and test repeated convergence on the selected OS.

### Key Dependencies to Address

- **Nginx cookbook 12.3.1:** Replace with Ansible `package`, `template`, `file`, `service`, and handler tasks. Preserve the required Nginx behavior without reproducing Chef cookbook internals.
- **Memcached cookbook 6.1.0:** Use distribution packages and a service task; explicitly define bind address and resource settings if needed.
- **RedisIO cookbook 7.2.4:** Use distribution packages or a maintained Ansible role. Model the password and Redis configuration declaratively and validate the reason for the current configuration rewrite.
- **SELinux cookbook 6.2.4:** On Fedora, use Ansible SELinux modules, contexts, and booleans. On Ubuntu, document the corresponding AppArmor behavior instead.
- **SSL certificate cookbook 2.1.0:** Verify whether it is unused policy baggage. Development self-signed certificates should be replaced by managed ACME or enterprise PKI certificates for any non-development environment.
- **PostgreSQL:** Use distribution-aware package tasks and PostgreSQL modules for database/user creation. Do not carry over `|| true` shell commands.
- **FastAPI source and requirements:** Pin a commit or release instead of tracking `main`; review and control the remote `requirements.txt` dependency set.
- **Vagrant/libvirt:** Keep Vagrant as a test harness if useful, but use an Ansible inventory and SSH connection as the provisioning interface.

### Security Considerations

- **Redis secret:** `cookbooks/cache/recipes/default.rb` contains the literal `redis_secure_password_123`. Move it to Ansible Vault or an external secret manager and rotate it.
- **PostgreSQL secret:** `cookbooks/fastapi-tutorial/recipes/default.rb` embeds `fastapi_password` in SQL, `.env`, and `DATABASE_URL`. Vault the password, make database creation idempotent, and restrict `.env` to a non-world-readable mode.
- **TLS keys:** `nginx-multisite` generates self-signed keys under `/etc/ssl/private` and certificates under `/etc/ssl/certs`. Preserve ownership and least-privilege modes; never commit production private keys. Define certificate renewal/rotation for production.
- **SSH:** The security recipe disables root login and password authentication using `sed`. Use validated Ansible-managed SSH configuration and confirm key-based recovery access before applying changes.
- **Firewall:** The current policy denies by default and allows SSH, HTTP, and HTTPS. Confirm management source ranges. Fedora should normally use firewalld rather than assuming UFW.
- **Fail2ban and sysctl:** Port the reviewed templates and settings only after confirming compatibility with the selected OS.
- **Application privileges:** The current FastAPI service runs as root and listens on `0.0.0.0:8000`. Create a dedicated service account, restrict direct exposure, and place it behind Nginx where appropriate.
- **Supply chain:** The bootstrap downloads Chef via `curl`, and the application tracks a mutable Git branch. Use verified repositories, pinned revisions, dependency scanning, and controlled artifacts.
- **Credential inventory by module:** `cache` contains a Redis password; `fastapi-tutorial` contains PostgreSQL credentials and an environment file; `nginx-multisite` creates TLS private keys. No encrypted data bags or Chef Vault usage were found in the reviewed files.

### Technical Challenges

- Resolve the Fedora-versus-Debian provisioning mismatch before role implementation.
- Reconcile Nginx attributes consumed by recipes with values in `solo.json`; the attribute file may contain additional defaults.
- Replace unsafe PostgreSQL shell commands and `|| true` with idempotent database/user tasks.
- Understand and declaratively reproduce the Redis configuration cleanup instead of copying a version-specific hack.
- Port the unreviewed Nginx, site, Fail2ban, and sysctl templates and validate `nginx -t` before reload handlers.
- Decide whether certificates are development-only or require ACME/enterprise PKI lifecycle management.
- Add deterministic hostname resolution for the three cluster-local test domains; the Vagrant `/etc/hosts` block is commented out.
- Define application update, health-check, rollback, and dependency-pinning behavior.
- Consolidate the overlapping Chef run-list sources (`Policyfile.rb`, `solo.json`, and the provisioning script) into one Ansible source of truth.

### Migration Order

1. Select the supported OS, create the Ansible inventory, establish SSH access, and build a repeatable VM test path.
2. Implement host security, SELinux/AppArmor policy, firewall, sysctl, Fail2ban, and safe SSH hardening.
3. Migrate Memcached and Redis, including vaulted authentication and service validation.
4. Migrate PostgreSQL and the FastAPI application, using a non-root systemd service and idempotent database provisioning.
5. Migrate Nginx multisite configuration, static content, TLS, virtual hosts, and reload handlers.
6. Run end-to-end parity and repeated-convergence tests, perform security review, then retire Chef/Berkshelf runtime dependencies.

Estimated effort is two to four weeks for one engineer. Allocate approximately 2-3 days for platform decisions, 3-5 days for security/cache roles, 3-5 days for PostgreSQL/FastAPI, 3-5 days for Nginx/TLS, and 3-7 days for testing, remediation, review, and documentation.

### Assumptions

- The three local cookbook directories listed in MODULE INVENTORY are the complete set of local modules because each is confirmed in the repository tree with `recipes/default.rb`.
- External Chef Supermarket cookbooks are dependencies and not local module directories.
- `solo.json` describes the intended development configuration, but `cookbooks/nginx-multisite/attributes/default.rb` must be reviewed before implementation to identify defaults and overrides.
- This is a development/test deployment, inferred from Vagrant, tutorial naming, and self-signed certificates; production requirements are not specified.
- The target OS, DNS, production inventory, certificate authority, secret manager, monitoring, backups, and CI test system are not specified and require stakeholder decisions.
- The remote FastAPI repository provides `requirements.txt` and `app.main:app`, but this must be verified and pinned.
- The exact contents of the Nginx, site, Fail2ban, and sysctl templates require a focused follow-up review.
- Team coordination should assign owners for platform/security, cache/database, application runtime, and Nginx/TLS; use a shared acceptance checklist and require security review before firewall/SSH changes or credential promotion.
