# Terraform infrastructure

This starter provisions a simple 3-node AWS environment for a k3s cluster:
- 1 control plane node
- 2 worker nodes
- a public subnet, IGW, and security group
- SSH + HTTP/HTTPS ingress

## Usage

```bash
cd terraform/root
terraform init
terraform plan -var='ami_id=ami-0...' -var='key_name=your-key'
terraform apply -var='ami_id=ami-0...' -var='key_name=your-key'
```

Replace the AMI ID with an Ubuntu 22.04 AMI for your region.
