variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "replicate_source_db_arn" {
  description = "ARN of the primary RDS instance in the primary region"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class for the read replica (e.g. db.t4g.micro)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_subnet_group_name" {
  description = "Name of the DB Subnet Group in the secondary/DR region"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of VPC Security Group IDs in the secondary/DR region"
  type        = list(string)
}

variable "max_allocated_storage" {
  description = "Maximum storage limit for storage autoscaling (GB)"
  type        = number
  default     = 50
}

variable "replica_lag_threshold_seconds" {
  description = "Threshold in seconds for ReplicaLag alarm (default 300s = 5 min RPO)"
  type        = number
  default     = 300
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to attach to RDS replica resources"
  type        = map(string)
  default     = {}
}
