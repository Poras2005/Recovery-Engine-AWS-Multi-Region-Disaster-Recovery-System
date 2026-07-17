terraform {
  backend "s3" {
    key            = "global/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = "ap-south-1"
}

variable "domain" {}
variable "primary_alb_dns" {}
variable "secondary_alb_dns" {}
variable "health_check_path" {}
variable "failover_ttl" {}
variable "app_name" {}

locals {
  # Treat placeholders, empty strings, or 'none' as having no domain configured
  has_domain = var.domain != "" && var.domain != "none" && var.domain != "<YOUR_DOMAIN>" && !can(regex("yourdomain", var.domain))
}

# Route 53 (Only deployed if a domain is configured)
resource "aws_route53_zone" "main" {
  count = local.has_domain ? 1 : 0
  name  = var.domain
}

resource "aws_route53_health_check" "primary" {
  count             = local.has_domain ? 1 : 0
  fqdn              = var.primary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = var.health_check_path
  failure_threshold = "3"
  request_interval  = "10"
}

resource "aws_route53_record" "primary" {
  count   = local.has_domain ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain
  type    = "CNAME"
  ttl     = var.failover_ttl

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "primary"
  records        = [var.primary_alb_dns]
  health_check_id = aws_route53_health_check.primary[0].id
}

resource "aws_route53_record" "secondary" {
  count   = local.has_domain ? 1 : 0
  zone_id = aws_route53_zone.main[0].zone_id
  name    = var.domain
  type    = "CNAME"
  ttl     = var.failover_ttl

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"
  records        = [var.secondary_alb_dns]
}

# CloudFront Distribution (Deployed if NO domain is configured, providing free CNAME-less failover)
resource "aws_cloudfront_distribution" "cdn" {
  count = local.has_domain ? 0 : 1

  origin {
    domain_name = var.primary_alb_dns
    origin_id   = "primary-alb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name = var.secondary_alb_dns
    origin_id   = "secondary-alb"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin_group {
    origin_id = "failover-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "primary-alb"
    }

    member {
      origin_id = "secondary-alb"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = ""

  default_cache_behavior {
    target_origin_id       = "failover-group"
    viewer_protocol_policy = "allow-all"

    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]

    # Forward all headers, cookies, and query strings to disable caching
    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.app_name}-cdn"
  }
}

# WAF - Basic regional WAF (Simplified)
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.app_name}-waf"
  description = "Basic WAF for ${var.app_name}"
  scope       = "REGIONAL"
  default_action {
    allow {}
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.app_name}-waf-metric"
    sampled_requests_enabled   = true
  }
}

output "has_domain" {
  value = local.has_domain
}

output "cloudfront_dns_name" {
  value = local.has_domain ? null : aws_cloudfront_distribution.cdn[0].domain_name
}

output "route53_domain" {
  value = local.has_domain ? var.domain : null
}
