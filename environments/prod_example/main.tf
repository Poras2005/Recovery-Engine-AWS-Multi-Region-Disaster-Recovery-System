# Primary Region Networking (Mumbai - Production)
module "primary_networking" {
  source = "../../modules/networking"

  providers = {
    aws = aws.primary
  }

  environment          = var.environment
  region_name          = "primary-${var.primary_region}"
  vpc_cidr             = var.primary_vpc_cidr
  public_subnet_cidrs  = var.primary_public_subnet_cidrs
  private_subnet_cidrs = var.primary_private_subnet_cidrs
  availability_zones   = var.primary_azs

  tags = {
    Region = var.primary_region
    Role   = "Primary-VPC-Production"
  }
}

# Secondary Region Networking (Singapore - Production DR)
module "secondary_networking" {
  source = "../../modules/networking"

  providers = {
    aws = aws.secondary
  }

  environment          = var.environment
  region_name          = "secondary-${var.secondary_region}"
  vpc_cidr             = var.secondary_vpc_cidr
  public_subnet_cidrs  = var.secondary_public_subnet_cidrs
  private_subnet_cidrs = var.secondary_private_subnet_cidrs
  availability_zones   = var.secondary_azs

  tags = {
    Region = var.secondary_region
    Role   = "Secondary-VPC-Production"
  }
}

# IAM Baseline Module
module "iam_baseline" {
  source = "../../modules/iam"

  providers = {
    aws = aws.primary
  }

  environment = var.environment
  tags = {
    Role = "IAM-Baseline-Production"
  }
}

# Primary RDS Instance (Mumbai - Production Multi-AZ)
module "primary_rds" {
  source = "../../modules/rds_primary"

  providers = {
    aws = aws.primary
  }

  environment             = var.environment
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  instance_class          = var.db_instance_class
  db_subnet_group_name    = module.primary_networking.db_subnet_group_name
  vpc_security_group_ids  = [module.primary_networking.rds_security_group_id]
  multi_az                = true
  backup_retention_period = 30

  tags = {
    Region = var.primary_region
    Role   = "Primary-Database-Production"
  }
}

# Secondary RDS Read Replica (Singapore - Production DR)
module "secondary_rds_replica" {
  source = "../../modules/rds_replica"

  providers = {
    aws = aws.secondary
  }

  environment                   = var.environment
  replicate_source_db_arn       = module.primary_rds.db_instance_arn
  instance_class                = var.db_instance_class
  db_subnet_group_name          = module.secondary_networking.db_subnet_group_name
  vpc_security_group_ids        = [module.secondary_networking.rds_security_group_id]
  replica_lag_threshold_seconds = 300 # 5 min RPO limit

  tags = {
    Region = var.secondary_region
    Role   = "Cross-Region-Read-Replica-Production"
  }
}

# Route53 Failover Routing Policy
module "route53_failover" {
  source = "../../modules/route53_failover"

  providers = {
    aws           = aws.primary
    aws.secondary = aws.secondary
  }

  environment          = var.environment
  domain_name          = var.domain_name
  is_private_zone      = true
  primary_vpc_id       = module.primary_networking.vpc_id
  primary_vpc_region   = var.primary_region
  secondary_vpc_id     = module.secondary_networking.vpc_id
  secondary_vpc_region = var.secondary_region
  primary_endpoint     = module.primary_rds.db_instance_address
  secondary_endpoint   = module.secondary_rds_replica.replica_instance_endpoint
  health_check_port    = 3306
  health_check_type    = "TCP"
  record_ttl           = 10

  tags = {
    Role = "Route53-Failover-Routing-Production"
  }
}

# Monitoring & SNS Alerting Subsystem
module "monitoring" {
  source = "../../modules/monitoring"

  providers = {
    aws = aws.primary
  }

  environment                   = var.environment
  primary_db_id                 = module.primary_rds.db_instance_id
  replica_db_id                 = module.secondary_rds_replica.replica_instance_id
  route53_health_check_id       = module.route53_failover.primary_health_check_id
  alert_email                   = var.alert_email
  replica_lag_threshold_seconds = 300

  tags = {
    Role = "Monitoring-Alerting-Production"
  }
}
