# SNS Topic for Disaster Recovery Alerts & Notifications
resource "aws_sns_topic" "dr_alerts" {
  name         = "recovery-engine-dr-alerts-${var.environment}"
  display_name = "Recovery-Engine Multi-Region DR Alerts (${var.environment})"

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-dr-alerts-${var.environment}"
      Environment = var.environment
      Role        = "SNS-DR-Notifications"
    }
  )
}

# SNS Topic Policy allowing CloudWatch Alarms to Publish
resource "aws_sns_topic_policy" "dr_alerts_policy" {
  arn = aws_sns_topic.dr_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

# SNS Email Subscription (Optional, created if alert_email is provided)
resource "aws_sns_topic_subscription" "email_sub" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarm: Primary RDS High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  alarm_name          = "recovery-engine-primary-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Triggers when Primary RDS CPU utilization exceeds 80% for 2 consecutive minutes."

  dimensions = {
    DBInstanceIdentifier = var.primary_db_id
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = merge(
    var.tags,
    {
      Name        = "primary-cpu-high-alarm-${var.environment}"
      Environment = var.environment
    }
  )
}

# CloudWatch Alarm: Primary RDS Low Free Storage Space (< 2GB)
resource "aws_cloudwatch_metric_alarm" "primary_low_storage" {
  alarm_name          = "recovery-engine-primary-low-storage-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in bytes
  alarm_description   = "Triggers when Primary RDS free storage space drops below 2GB."

  dimensions = {
    DBInstanceIdentifier = var.primary_db_id
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = merge(
    var.tags,
    {
      Name        = "primary-low-storage-alarm-${var.environment}"
      Environment = var.environment
    }
  )
}

# CloudWatch Alarm: RDS Cross-Region Replication Lag (RPO Threshold Breach)
resource "aws_cloudwatch_metric_alarm" "replica_lag_rpo_breach" {
  alarm_name          = "recovery-engine-replica-lag-rpo-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replica_lag_threshold_seconds
  alarm_description   = "Triggers when RDS Cross-Region replication lag exceeds the target RPO threshold (${var.replica_lag_threshold_seconds}s / 5 min)."

  dimensions = {
    DBInstanceIdentifier = var.replica_db_id
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = merge(
    var.tags,
    {
      Name        = "replica-lag-rpo-alarm-${var.environment}"
      Environment = var.environment
    }
  )
}

# CloudWatch Alarm: Route53 Primary Endpoint Health Check Failure
resource "aws_cloudwatch_metric_alarm" "route53_health_failure" {
  count               = var.route53_health_check_id != "" ? 1 : 0
  alarm_name          = "recovery-engine-route53-health-failure-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Triggers when Route53 Primary Endpoint health check fails (Status < 1)."

  dimensions = {
    HealthCheckId = var.route53_health_check_id
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = merge(
    var.tags,
    {
      Name        = "route53-health-failure-alarm-${var.environment}"
      Environment = var.environment
    }
  )
}

# Unified Multi-Region Disaster Recovery CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "dr_dashboard" {
  dashboard_name = "recovery-engine-dr-dashboard-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", var.replica_db_id, { region = "ap-southeast-1" }]
          ]
          period = 60
          stat   = "Maximum"
          region = "ap-southeast-1"
          title  = "RDS Cross-Region Replication Lag (Seconds) - Target RPO: <= 300s"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.primary_db_id, { region = "ap-south-1" }]
          ]
          period = 60
          stat   = "Average"
          region = "ap-south-1"
          title  = "Primary RDS CPU Utilization (%) - Mumbai"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.primary_db_id, { region = "ap-south-1" }]
          ]
          period = 60
          stat   = "Average"
          region = "ap-south-1"
          title  = "Primary RDS Free Storage Space (Bytes)"
        }
      }
    ]
  })
}

