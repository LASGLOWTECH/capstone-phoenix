output "endpoint" {
  description = "Endpoint address of the RDS instance."
  value       = aws_db_instance.main.endpoint
}

output "port" {
  description = "Port used by the RDS instance."
  value       = aws_db_instance.main.port
}

output "arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.main.arn
}