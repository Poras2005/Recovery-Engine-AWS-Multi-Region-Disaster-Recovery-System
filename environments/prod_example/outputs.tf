output "primary_vpc_id" {
  description = "VPC ID of the primary region (Mumbai Production)"
  value       = module.primary_networking.vpc_id
}

output "secondary_vpc_id" {
  description = "VPC ID of the secondary region (Singapore Production DR)"
  value       = module.secondary_networking.vpc_id
}

output "orchestrator_role_arn" {
  description = "ARN of the Failover Orchestrator IAM Role"
  value       = module.iam_baseline.orchestrator_role_arn
}

output "primary_db_endpoint" {
  description = "Connection endpoint of the primary production RDS instance"
  value       = module.primary_rds.db_instance_endpoint
}

output "secondary_db_replica_endpoint" {
  description = "Connection endpoint of the secondary production RDS read replica"
  value       = module.secondary_rds_replica.replica_instance_endpoint
}

output "route53_db_failover_fqdn" {
  description = "Failover DNS record FQDN (e.g. db.recovery-engine-prod.internal)"
  value       = module.route53_failover.db_failover_fqdn
}

output "monitoring_sns_topic_arn" {
  description = "ARN of the Disaster Recovery SNS Alert Topic"
  value       = module.monitoring.sns_topic_arn
}

output "monitoring_cloudwatch_dashboard_name" {
  description = "Name of the Multi-Region CloudWatch DR Dashboard"
  value       = module.monitoring.dashboard_name
}
