# Primary Private Hosted Zone
resource "aws_route53_zone" "main" {
  name          = var.domain_name
  comment       = "Recovery-Engine Multi-Region Private Hosted Zone (${var.environment})"
  force_destroy = true

  dynamic "vpc" {
    for_each = var.is_private_zone ? [1] : []
    content {
      vpc_id     = var.primary_vpc_id
      vpc_region = var.primary_vpc_region
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "route53-private-zone-${var.environment}"
      Environment = var.environment
    }
  )
}

# Cross-Region VPC Association Authorization (Owning Primary Region)
resource "aws_route53_vpc_association_authorization" "secondary_auth" {
  count      = var.is_private_zone ? 1 : 0
  zone_id    = aws_route53_zone.main.zone_id
  vpc_id     = var.secondary_vpc_id
  vpc_region = var.secondary_vpc_region
}

# Cross-Region VPC Zone Association (Secondary Region)
resource "aws_route53_zone_association" "secondary" {
  count      = var.is_private_zone ? 1 : 0
  zone_id    = aws_route53_zone.main.zone_id
  vpc_id     = aws_route53_vpc_association_authorization.secondary_auth[0].vpc_id
  vpc_region = aws_route53_vpc_association_authorization.secondary_auth[0].vpc_region
}

# Route53 Health Check for Primary Region Endpoint
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_endpoint
  port              = var.health_check_port
  type              = var.health_check_type
  request_interval  = var.health_check_request_interval
  failure_threshold = var.health_check_failure_threshold

  tags = merge(
    var.tags,
    {
      Name        = "route53-primary-health-check-${var.environment}"
      Environment = var.environment
    }
  )
}

# Primary Route53 Failover Record Set
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.${var.domain_name}"
  type    = "CNAME"
  ttl     = var.record_ttl

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary-mumbai"
  records         = [var.primary_endpoint]
  health_check_id = aws_route53_health_check.primary.id
}

# Secondary Route53 Failover Record Set
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.${var.domain_name}"
  type    = "CNAME"
  ttl     = var.record_ttl

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary-singapore"
  records        = [var.secondary_endpoint]
}
