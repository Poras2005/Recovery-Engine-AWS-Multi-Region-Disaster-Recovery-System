terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary Region Provider (Mumbai)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "Recovery-Engine-AWS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      RegionRole  = "Primary"
    }
  }
}

# Secondary / DR Region Provider (Singapore)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = "Recovery-Engine-AWS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      RegionRole  = "Secondary-DR"
    }
  }
}
