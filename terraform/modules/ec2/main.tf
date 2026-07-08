variable "vpc_id" { type = string }
variable "private_subnets" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "target_group_arn" { type = string }
variable "app_name" { type = string }
variable "region" { type = string }
variable "instance_type" { type = string }
variable "min_size" { type = number }
variable "max_size" { type = number }
variable "desired_size" { type = number }
variable "account_id" { type = string }
variable "image_tag" { type = string }
variable "use_spot" { default = false }
variable "db_secret_arn" { type = string }
variable "db_host" { type = string }

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.app_name}-ec2-sg-${var.region}"
  vpc_id      = var.vpc_id
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.app_name}-ec2-role-${var.region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_policy" "secrets_read" {
  name        = "${var.app_name}-secrets-read-${var.region}"
  description = "Allow reading DB secret"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["secretsmanager:GetSecretValue"]
      Effect   = "Allow"
      Resource = [var.db_secret_arn]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.app_name}-ec2-profile-${var.region}"
  role = aws_iam_role.ec2_role.name
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.app_name}-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.ec2_profile.name }
  vpc_security_group_ids = [aws_security_group.ec2.id]

  instance_market_options {
    market_type = var.use_spot ? "spot" : null
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              
              # Fetch DB Password securely
              DB_PASS=$(aws secretsmanager get-secret-value --secret-id ${var.db_secret_arn} --query SecretString --output text --region ${var.region})

              aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com
              docker pull ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.app_name}:${var.image_tag}
              docker run -d -p 5000:5000 -e AWS_REGION=${var.region} -e DB_PASSWORD=$DB_PASS -e DB_HOST=${var.db_host} ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.app_name}:${var.image_tag}
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.app_name}-instance"
      Env  = "production"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "dr-asg-${var.region == "ap-south-1" ? "mumbai" : "singapore"}"
  vpc_zone_identifier = var.private_subnets
  target_group_arns   = [var.target_group_arn]
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_size

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    
    key                 = "Name"
    value               = "${var.app_name}-asg"
    propagate_at_launch = true
  }
}

output "asg_name" { value = aws_autoscaling_group.app.name }
output "security_group_id" { value = aws_security_group.ec2.id }
