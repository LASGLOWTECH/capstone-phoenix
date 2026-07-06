output "app_sg_id" {
  description = "Security group ID for application servers."
  value       = aws_security_group.backend.id
}

output "db_sg_id" {
  description = "Security group ID for database servers."
  value       = aws_security_group.rds.id
}

output "frontend_security_group_id" {
  description = "Security group ID for frontend servers."
  value       = aws_security_group.frontend.id
}

output "backend_security_group_id" {
  description = "Security group ID for backend servers."
  value       = aws_security_group.backend.id
}

output "database_security_group_id" {
  description = "Security group ID for database servers."
  value       = aws_security_group.rds.id
}
