output "vpc_id" {
  description = "The ID of the VPC created by this module."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block assigned to the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets created by this module."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets created by this module."
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "The ID of the internet gateway created by this module."
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "The ID of the NAT gateway created by this module."
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT gateway created by this module."
  value       = aws_eip.nat.public_ip
}
