variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

# Primary Region Variables
variable "primary_region" {
  description = "AWS Primary region code"
  type        = string
  default     = "ap-south-1"
}

variable "primary_vpc_cidr" {
  description = "VPC CIDR for primary region"
  type        = string
  default     = "10.10.0.0/16"
}

variable "primary_public_subnet_cidrs" {
  description = "Public subnet CIDRs for primary region"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "primary_private_subnet_cidrs" {
  description = "Private subnet CIDRs for primary region"
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "primary_azs" {
  description = "Availability zones for primary region"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# Secondary Region Variables
variable "secondary_region" {
  description = "AWS Secondary (DR) region code"
  type        = string
  default     = "ap-southeast-1"
}

variable "secondary_vpc_cidr" {
  description = "VPC CIDR for secondary region"
  type        = string
  default     = "10.20.0.0/16"
}

variable "secondary_public_subnet_cidrs" {
  description = "Public subnet CIDRs for secondary region"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "secondary_private_subnet_cidrs" {
  description = "Private subnet CIDRs for secondary region"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "secondary_azs" {
  description = "Availability zones for secondary region"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

# Database Variables
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
  default     = "ChangeMeInTfVars123!"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

# Domain & Route53 Variables
variable "domain_name" {
  description = "Route53 Private Hosted Zone domain name"
  type        = string
  default     = "recovery-engine.internal"
}


