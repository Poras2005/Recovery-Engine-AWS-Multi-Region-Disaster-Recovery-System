# Cross-Region Read Replica in Secondary Region (Singapore)
resource "aws_db_instance" "replica" {
  identifier                  = "recovery-engine-replica-db-${var.environment}"
  replicate_source_db         = var.replicate_source_db_arn
  instance_class              = var.instance_class
  max_allocated_storage       = var.max_allocated_storage
  db_subnet_group_name        = var.db_subnet_group_name
  vpc_security_group_ids      = var.vpc_security_group_ids
  multi_az                    = false
  auto_minor_version_upgrade  = true
  publicly_accessible         = false
  skip_final_snapshot         = var.skip_final_snapshot

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-replica-db-${var.environment}"
      Role        = "Cross-Region-Read-Replica"
      Environment = var.environment
    }
  )
}

# CloudWatch Alarm for Replication Lag (Target RPO Check)
resource "aws_cloudwatch_metric_alarm" "replica_lag_alarm" {
  alarm_name          = "recovery-engine-rds-replica-lag-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replica_lag_threshold_seconds
  alarm_description   = "Fires when RDS cross-region replication lag exceeds the target RPO threshold (${var.replica_lag_threshold_seconds}s)"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.replica.identifier
  }

  tags = merge(
    var.tags,
    {
      Name        = "rds-replica-lag-alarm-${var.environment}"
      Environment = var.environment
    }
  )
}
