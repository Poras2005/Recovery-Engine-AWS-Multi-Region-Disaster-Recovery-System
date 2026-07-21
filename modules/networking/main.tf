# VPC Creation
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-vpc-${var.region_name}-${var.environment}"
      Environment = var.environment
      RegionLabel = var.region_name
    }
  )
}

# Internet Gateway for public access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-igw-${var.region_name}-${var.environment}"
      Environment = var.environment
    }
  )
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-public-subnet-${count.index + 1}-${var.region_name}"
      Type        = "Public"
      Environment = var.environment
    }
  )
}

# Private Subnets (for RDS and internal microservices)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-private-subnet-${count.index + 1}-${var.region_name}"
      Type        = "Private"
      Environment = var.environment
    }
  )
}

# DB Subnet Group for RDS placement
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "recovery-engine-db-subnets-${var.region_name}-${var.environment}"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-db-subnet-group-${var.region_name}"
      Environment = var.environment
    }
  )
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-public-rt-${var.region_name}"
      Environment = var.environment
    }
  )
}

# Associate Public Subnets to Public Route Table
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table for Private Subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-private-rt-${var.region_name}"
      Environment = var.environment
    }
  )
}

# Associate Private Subnets to Private Route Table
resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for Database (RDS)
resource "aws_security_group" "rds" {
  name        = "recovery-engine-rds-sg-${var.region_name}-${var.environment}"
  description = "Security group for RDS database instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL/PostgreSQL traffic within VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-rds-sg-${var.region_name}"
      Environment = var.environment
    }
  )
}

# Security Group for Application / Controller Access
resource "aws_security_group" "app" {
  name        = "recovery-engine-app-sg-${var.region_name}-${var.environment}"
  description = "Security group for application layer / bastion access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTPS within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow HTTP within VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "recovery-engine-app-sg-${var.region_name}"
      Environment = var.environment
    }
  )
}
