output "replica_instance_id" {
  description = "The ID of the RDS cross-region read replica instance"
  value       = aws_db_instance.replica.id
}

output "replica_instance_arn" {
  description = "The ARN of the RDS cross-region read replica instance"
  value       = aws_db_instance.replica.arn
}

output "replica_instance_endpoint" {
  description = "The connection endpoint of the RDS read replica instance"
  value       = aws_db_instance.replica.endpoint
}

output "replica_lag_alarm_arn" {
  description = "ARN of the CloudWatch replication lag alarm"
  value       = aws_cloudwatch_metric_alarm.replica_lag_alarm.arn
}
