# Running generated Molecule scenarios

Install Molecule, its Podman driver plugin in the same Python environment, and Podman. For a uv-managed environment:

```bash
uv pip install --python "$(command -v python)" molecule 'molecule-plugins[podman]'
ANSIBLE_COLLECTIONS_PATH="$PWD/collections" \
  ansible-galaxy collection install -r molecule/requirements.yml
molecule test --scenario-name <module>
```

Run from the Ansible project root. Scenarios create privileged, disposable Linux
containers using Molecule's native Podman driver; do not point them at production
inventory. Set `X2A_MOLECULE_IMAGE` to use another Linux image that includes systemd at
`/sbin/init` and a supported `dnf` or `apt-get` package manager. Podman systemd
mode is enabled for the disposable container. Tests bootstrap Python before
applying the actual project deployment playbook. The converter generates and
statically validates scenarios but does not execute them; developer/CI results
are the runtime acceptance signal. Windows hosts require a separate future profile.
