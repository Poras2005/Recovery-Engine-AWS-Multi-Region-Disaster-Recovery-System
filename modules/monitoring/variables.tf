variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "primary_db_id" {
  description = "DB Instance Identifier for the Primary RDS instance"
  type        = string
}

variable "replica_db_id" {
  description = "DB Instance Identifier for the Secondary RDS Replica instance"
  type        = string
}

variable "route53_health_check_id" {
  description = "Route53 Primary Endpoint Health Check ID"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Optional email address to receive SNS alert notifications"
  type        = string
  default     = ""
}

variable "replica_lag_threshold_seconds" {
  description = "Maximum allowed replication lag in seconds before RPO breach alarm fires (default: 300s / 5 min)"
  type        = number
  default     = 300
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
