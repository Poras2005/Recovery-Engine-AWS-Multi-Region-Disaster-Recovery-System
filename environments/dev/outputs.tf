output "primary_vpc_id" {
  description = "VPC ID of the primary region (Mumbai)"
  value       = module.primary_networking.vpc_id
}

output "primary_private_subnet_ids" {
  description = "Private subnet IDs of the primary region"
  value       = module.primary_networking.private_subnet_ids
}

output "primary_db_subnet_group" {
  description = "RDS DB subnet group name in primary region"
  value       = module.primary_networking.db_subnet_group_name
}

output "primary_rds_sg_id" {
  description = "RDS Security group ID in primary region"
  value       = module.primary_networking.rds_security_group_id
}

output "secondary_vpc_id" {
  description = "VPC ID of the secondary region (Singapore)"
  value       = module.secondary_networking.vpc_id
}

output "secondary_private_subnet_ids" {
  description = "Private subnet IDs of the secondary region"
  value       = module.secondary_networking.private_subnet_ids
}

output "secondary_db_subnet_group" {
  description = "RDS DB subnet group name in secondary region"
  value       = module.secondary_networking.db_subnet_group_name
}

output "secondary_rds_sg_id" {
  description = "RDS Security group ID in secondary region"
  value       = module.secondary_networking.rds_security_group_id
}

output "orchestrator_role_arn" {
  description = "ARN of the Failover Orchestrator IAM Role"
  value       = module.iam_baseline.orchestrator_role_arn
}

output "primary_db_arn" {
  description = "ARN of the primary RDS instance (used for cross-region replication setup)"
  value       = module.primary_rds.db_instance_arn
}

output "primary_db_endpoint" {
  description = "Connection endpoint of the primary RDS instance"
  value       = module.primary_rds.db_instance_endpoint
}

output "secondary_db_replica_arn" {
  description = "ARN of the secondary RDS read replica instance"
  value       = module.secondary_rds_replica.replica_instance_arn
}

output "secondary_db_replica_endpoint" {
  description = "Connection endpoint of the secondary RDS read replica instance"
  value       = module.secondary_rds_replica.replica_instance_endpoint
}

output "replica_lag_alarm_arn" {
  description = "ARN of the CloudWatch replication lag alarm"
  value       = module.secondary_rds_replica.replica_lag_alarm_arn
}

output "route53_zone_id" {
  description = "Route53 Private Hosted Zone ID"
  value       = module.route53_failover.zone_id
}

output "route53_db_failover_fqdn" {
  description = "Failover DNS record FQDN (e.g. db.recovery-engine.internal)"
  value       = module.route53_failover.db_failover_fqdn
}

output "route53_primary_health_check_id" {
  description = "Route53 primary endpoint health check ID"
  value       = module.route53_failover.primary_health_check_id
}

output "monitoring_sns_topic_arn" {
  description = "ARN of the Disaster Recovery SNS Alert Topic"
  value       = module.monitoring.sns_topic_arn
}

output "monitoring_primary_cpu_alarm_arn" {
  description = "ARN of the Primary RDS High CPU CloudWatch Alarm"
  value       = module.monitoring.primary_cpu_alarm_arn
}

output "monitoring_cloudwatch_dashboard_name" {
  description = "Name of the Multi-Region CloudWatch DR Dashboard"
  value       = module.monitoring.dashboard_name
}





