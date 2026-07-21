variable "environment" {
  description = "Environment name (e.g. dev, prod)"
  type        = string
}

variable "engine" {
  description = "Database engine (e.g. mysql, postgres)"
  type        = string
  default     = "mysql"
}

variable "engine_version" {
  description = "Database engine version"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t4g.micro for cost savings)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage limit for storage autoscaling (GB)"
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
  default     = "recoverydb"
}

variable "db_username" {
  description = "Master username for database"
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for database"
  type        = string
  sensitive   = true
}

variable "db_subnet_group_name" {
  description = "Name of the DB Subnet Group from networking module"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "List of VPC Security Group IDs to attach to RDS"
  type        = list(string)
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for high availability in primary region"
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Backup retention period in days (must be > 0 for cross-region replication)"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (useful for dev/test torn downs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to attach to RDS primary resources"
  type        = map(string)
  default     = {}
}
