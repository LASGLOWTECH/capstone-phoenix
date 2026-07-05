output "vpc_id" {
  description = "ID of the VPC created for the k3s cluster."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs created for the cluster."
  value       = aws_subnet.public[*].id
}

output "control_plane_public_ip" {
  description = "Public IP of the k3s control-plane node."
  value       = aws_instance.k3s_nodes[0].public_ip
}

output "worker_public_ips" {
  description = "Public IPs of the k3s worker nodes."
  value       = [for i, instance in aws_instance.k3s_nodes : instance.public_ip if i > 0]
}

output "node_public_ips" {
  description = "Public IPs of all k3s nodes."
  value       = aws_instance.k3s_nodes[*].public_ip
}

output "node_private_ips" {
  description = "Private IPs of all k3s nodes."
  value       = aws_instance.k3s_nodes[*].private_ip
}
