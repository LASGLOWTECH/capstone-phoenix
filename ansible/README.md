# Ansible cluster bootstrap

This playbook provisions a k3s cluster across three Ubuntu nodes.

## Usage

```bash
cd infra/ansible
ansible-playbook -i inventory/dev.yaml playbooks/site.yaml
```

Update the inventory hosts with the public IPs from Terraform before running it.
