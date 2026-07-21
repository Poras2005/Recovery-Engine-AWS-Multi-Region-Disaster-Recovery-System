# Primary Multi-AZ RDS Instance
resource "aws_db_instance" "primary" {
  identifier                  = "recovery-engine-primary-db-${var.environment}"
  engine                      = var.engine
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  db_name                     = var.db_name
  username                    = var.db_username
  password                    = var.db_password
  db_subnet_group_name        = var.db_subnet_group_name
  vpc_security_group_ids      = var.vpc_security_group_ids
  multi_az                    = var.multi_az
  backup_retention_period     = var.backup_retention_period # Mandatory for Cross-Region Read Replica
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  publicly_accessible         = false
  copy_tags_to_snapshot       = true
  skip_final_snapshot         = var.skip_final_snapshot

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-primary-db-${var.environment}"
      Role        = "Primary-Database"
      Environment = var.environment
    }
  )
}
