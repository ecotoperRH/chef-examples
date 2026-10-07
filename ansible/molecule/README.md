# Running generated Molecule scenarios

Install Molecule and Podman, then install the scenario's test-only collection:

```bash
ANSIBLE_COLLECTIONS_PATH="$PWD/collections" \
  ansible-galaxy collection install -r molecule/requirements.yml
molecule test --scenario-name <module>
```

Run from the Ansible project root. Scenarios create privileged, disposable Linux
containers with Podman; do not point them at production inventory. Set
`X2A_MOLECULE_IMAGE` to use another Linux image with `/usr/sbin/init` and a
supported `dnf` or `apt-get` package manager. Tests bootstrap Python before
applying the actual project deployment playbook. The converter generates and
statically validates scenarios but does not execute them; developer/CI results
are the runtime acceptance signal. Windows hosts require a separate future profile.
