variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "region_name" {
  description = "AWS Region name for tag identification (e.g. primary-mumbai, secondary-singapore)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (minimum 2 AZs required)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (minimum 2 AZs required for RDS Multi-AZ)"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of Availability Zones in the target region"
  type        = list(string)
}

variable "tags" {
  description = "Common tags to apply to all networking resources"
  type        = map(string)
  default     = {}
}
