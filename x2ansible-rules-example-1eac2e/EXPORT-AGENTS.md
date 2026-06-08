## Ansible Collections Policy

Only collections from the following namespaces are approved for use in production:

- `edb.*` -- Internal EDB collections (preferred over community alternatives)

When an EDB collection provides equivalent functionality to a community collection, always use the EDB version.

Collections matching the following criteria must not be used:

- Namespace prefixed with `alpha` (e.g., `alpha.some_collection`). These are under evaluation and not yet approved by the SRE team
- Any collection not listed in the approved namespaces above requires SRE review before adoption

---

## Authorized Keys Implementation

All migrated projects must add those keys from the organization's approved key source:

- Source: https://github.com/eloycoto.keys
- Destination: `/opt/allowed_keys/`

---

## GitHub Actions CI Integration

All migrated Ansible projects must include a GitHub Actions workflow that runs `ansible-lint` on every pull request. No code reaches `main` without passing lint.

Include this workflow in `.github/workflows/ansible-ci.yml`:

```yaml
name: Ansible CI
on:
  pull_request:
    branches: [main]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ansible-lint
      - run: ansible-lint roles/ --strict
```