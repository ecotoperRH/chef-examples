

## Adversarial Review Findings

**Agent:** Dangerous Operations

**Summary:** One critical finding was identified: configuration changes trigger an unguarded Memcached restart, flushing in-memory cache contents and interrupting clients without maintenance, rolling deployment, validation, or health-check safeguards. No deletion, destructive storage operations, or explicit stop/disable tasks were detected.

### [CRITICAL] handlers/main.yml:2-5; triggered by tasks/memcached.yml:8-22

The "Configure Memcached runtime options" task notifies a "Restart Memcached" handler whenever the managed configuration block changes. The handler performs a full service restart. Because Memcached is in-memory, this immediately evicts all cached data and interrupts active clients. There are no safety controls such as an explicit restart-approval variable or maintenance-window gate, node draining and serial/rolling execution for clustered deployments, configuration validation before restart, service health verification afterward, or documentation/acknowledgement of the cache flush. Suggested remediation: default a variable such as cache_allow_restart to false and require explicit approval during maintenance; drain nodes and use rolling execution in clustered deployments; validate configuration and check health around the restart; use a non-disruptive reload where supported, otherwise explicitly document the disruptive cache flush.

**Evidence:**
```
tasks/memcached.yml uses ansible.builtin.blockinfile to manage runtime options and includes `notify: Restart Memcached`. handlers/main.yml defines `Restart Memcached` with ansible.builtin.service, `name: memcached`, and `state: restarted`.
```

---