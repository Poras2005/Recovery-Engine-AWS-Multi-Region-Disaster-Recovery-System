output "sns_topic_arn" {
  description = "ARN of the Disaster Recovery SNS Alert Topic"
  value       = aws_sns_topic.dr_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the Disaster Recovery SNS Alert Topic"
  value       = aws_sns_topic.dr_alerts.name
}

output "primary_cpu_alarm_arn" {
  description = "ARN of the Primary RDS High CPU CloudWatch Alarm"
  value       = aws_cloudwatch_metric_alarm.primary_cpu_high.arn
}

output "replica_lag_alarm_arn" {
  description = "ARN of the Cross-Region Replica Lag CloudWatch Alarm"
  value       = aws_cloudwatch_metric_alarm.replica_lag_rpo_breach.arn
}

output "route53_health_alarm_arn" {
  description = "ARN of the Route53 Primary Health Check CloudWatch Alarm"
  value       = length(aws_cloudwatch_metric_alarm.route53_health_failure) > 0 ? aws_cloudwatch_metric_alarm.route53_health_failure[0].arn : ""
}

output "dashboard_name" {
  description = "Name of the CloudWatch Disaster Recovery Dashboard"
  value       = aws_cloudwatch_dashboard.dr_dashboard.dashboard_name
}

