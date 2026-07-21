variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "domain_name" {
  description = "Private domain name for the hosted zone (e.g. recovery-engine.internal)"
  type        = string
  default     = "recovery-engine.internal"
}

variable "is_private_zone" {
  description = "Set to true for Route53 Private Hosted Zone (cost-conscious default), or false for Public Hosted Zone"
  type        = bool
  default     = true
}

variable "primary_vpc_id" {
  description = "VPC ID of the primary region (Mumbai)"
  type        = string
}

variable "primary_vpc_region" {
  description = "AWS region for primary VPC"
  type        = string
  default     = "ap-south-1"
}

variable "secondary_vpc_id" {
  description = "VPC ID of the secondary region (Singapore)"
  type        = string
}

variable "secondary_vpc_region" {
  description = "AWS region for secondary VPC"
  type        = string
  default     = "ap-southeast-1"
}

variable "primary_endpoint" {
  description = "Primary database endpoint address or FQDN (Mumbai)"
  type        = string
}

variable "secondary_endpoint" {
  description = "Secondary database endpoint address or FQDN (Singapore)"
  type        = string
}

variable "health_check_port" {
  description = "Port to perform health check on (e.g. 3306 for MySQL/Postgres or 80/443 for HTTP)"
  type        = number
  default     = 3306
}

variable "health_check_type" {
  description = "Route53 health check protocol type (TCP, HTTP, HTTPS)"
  type        = string
  default     = "TCP"
}

variable "health_check_request_interval" {
  description = "The number of seconds between health check requests (10 or 30)"
  type        = number
  default     = 30
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures required to trigger failover"
  type        = number
  default     = 3
}

variable "record_ttl" {
  description = "TTL in seconds for Route53 failover records (low TTL ensures rapid DNS failover)"
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags to attach to Route53 resources"
  type        = map(string)
  default     = {}
}
