terraform {
  backend "s3" {
    key            = "singapore/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "mumbai"
  region = "ap-south-1"
}

variable "account_id" {}
variable "app_name" {}
variable "instance_type" {}
variable "min_size" {}
variable "max_size" {}
variable "desired_size" {}
variable "db_password" {}

# Find the primary DB in Mumbai
data "aws_db_instance" "primary" {
  provider            = aws.mumbai
  db_instance_identifier = "${var.app_name}-db-ap-south-1"
}

module "vpc" {
  source   = "../../modules/vpc"
  region   = "ap-southeast-1"
  app_name = var.app_name
}

module "alb" {
  source         = "../../modules/alb"
  vpc_id         = module.vpc.vpc_id
  public_subnets = module.vpc.public_subnets
  app_name       = var.app_name
  region         = "ap-southeast-1"
}

module "ec2" {
  source           = "../../modules/ec2"
  vpc_id           = module.vpc.vpc_id
  private_subnets  = module.vpc.public_subnets
  alb_sg_id        = module.alb.security_group_id
  target_group_arn = module.alb.target_group_arn
  app_name         = var.app_name
  region           = "ap-southeast-1"
  instance_type    = var.instance_type
  min_size         = var.min_size
  max_size         = var.max_size
  desired_size     = var.desired_size
  account_id       = var.account_id
  image_tag        = "latest"
  db_secret_arn    = module.rds.secret_arn
  db_host          = module.rds.db_endpoint
  use_spot         = true
}

module "rds" {
  source              = "../../modules/rds"
  vpc_id              = module.vpc.vpc_id
  private_subnets     = module.vpc.private_subnets
  ec2_sg_id           = module.ec2.security_group_id
  app_name            = var.app_name
  region              = "ap-southeast-1"
  replicate_source_db = data.aws_db_instance.primary.db_instance_arn
  db_password         = var.db_password # Replica might not need it, but the module requires it
}

module "monitoring" {
  source   = "../../modules/monitoring"
  app_name = var.app_name
  region   = "ap-southeast-1"
}

output "alb_dns_name" { value = module.alb.dns_name }
output "alb_zone_id" { value = module.alb.zone_id }
