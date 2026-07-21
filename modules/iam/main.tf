# Assume Role Policy for Orchestrator execution role (Lambda or EC2/SSM execution)
data "aws_iam_policy_document" "orchestrator_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

# Least-Privilege IAM Policy for DR Failover Orchestrator
resource "aws_iam_policy" "orchestrator_policy" {
  name        = "recovery-engine-orchestrator-policy-${var.environment}"
  description = "Permissions for failover orchestrator to promote RDS read replicas, update Route53, and check CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSFailoverPermissions"
        Effect = "Allow"
        Action = [
          "rds:PromoteReadReplica",
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:DescribeDBLogFiles",
          "rds:DescribeEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53DNSUpdatePermissions"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:GetHealthCheck",
          "route53:GetHealthCheckStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsAndLogging"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSAlertNotification"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# IAM Role for Orchestrator
resource "aws_iam_role" "orchestrator_role" {
  name               = "recovery-engine-orchestrator-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.orchestrator_assume_role.json
  tags               = var.tags
}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "orchestrator_attach" {
  role       = aws_iam_role.orchestrator_role.name
  policy_arn = aws_iam_policy.orchestrator_policy.arn
}
