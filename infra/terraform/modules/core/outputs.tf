output "availability_zones" {   
  description = "List of availability zones in the current region."
  value       = data.aws_availability_zones.available.names
}

output "ubuntu_ami_id" {
  description = "The most recent Ubuntu AMI ID for the specified region."
  value       = data.aws_ami.ubuntu.id
}   

output "ubuntu_ami_name" {
  description = "The name of the most recent Ubuntu AMI for the specified region."
  value       = data.aws_ami.ubuntu.name
}

output "current_account_id" {
  description = "The AWS account ID of the current caller."
  value       = data.aws_caller_identity.current.account_id
}

output "current_region" {
  description = "The AWS region of the current caller."
  value       = data.aws_region.current.name
}