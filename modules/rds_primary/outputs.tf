output "db_instance_id" {
  description = "The ID of the primary RDS instance"
  value       = aws_db_instance.primary.id
}

output "db_instance_arn" {
  description = "The ARN of the primary RDS instance (required for cross-region replica creation)"
  value       = aws_db_instance.primary.arn
}

output "db_instance_endpoint" {
  description = "The connection endpoint of the primary RDS instance"
  value       = aws_db_instance.primary.endpoint
}

output "db_instance_address" {
  description = "The hostname address of the primary RDS instance"
  value       = aws_db_instance.primary.address
}
