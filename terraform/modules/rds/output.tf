output "endpoint" {
  description = "Endpoint address of the RDS instance."
  value       = aws_db_instance.default.endpoint
}

output "port" {
  description = "Port used by the RDS instance."
  value       = aws_db_instance.default.port
}

output "arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.default.arn
}
