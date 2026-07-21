output "orchestrator_role_arn" {
  description = "ARN of the Failover Orchestrator IAM Role"
  value       = aws_iam_role.orchestrator_role.arn
}

output "orchestrator_role_name" {
  description = "Name of the Failover Orchestrator IAM Role"
  value       = aws_iam_role.orchestrator_role.name
}

output "orchestrator_policy_arn" {
  description = "ARN of the Failover Orchestrator IAM Policy"
  value       = aws_iam_policy.orchestrator_policy.arn
}
