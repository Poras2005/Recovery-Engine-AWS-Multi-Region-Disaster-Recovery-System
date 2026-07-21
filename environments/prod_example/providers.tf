terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary Region Provider (Mumbai - Production)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = "Recovery-Engine-AWS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      RegionRole  = "Primary-Production"
    }
  }
}

# Secondary / DR Region Provider (Singapore - Production DR)
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = "Recovery-Engine-AWS"
      Environment = var.environment
      ManagedBy   = "Terraform"
      RegionRole  = "Secondary-DR-Production"
    }
  }
}
