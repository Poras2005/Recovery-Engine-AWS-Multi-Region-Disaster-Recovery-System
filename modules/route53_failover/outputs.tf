output "zone_id" {
  description = "The Hosted Zone ID of the Route53 domain"
  value       = aws_route53_zone.main.zone_id
}

output "zone_name" {
  description = "The Hosted Zone domain name"
  value       = aws_route53_zone.main.name
}

output "db_failover_fqdn" {
  description = "The FQDN of the failover DNS record (e.g. db.recovery-engine.internal)"
  value       = aws_route53_record.primary.fqdn
}

output "primary_health_check_id" {
  description = "ID of the Route53 primary endpoint health check"
  value       = aws_route53_health_check.primary.id
}
