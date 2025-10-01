# Terraform configuration per MapReduce su AWS
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# VPC
resource "aws_vpc" "mapreduce_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "mapreduce_igw" {
  vpc_id = aws_vpc.mapreduce_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.mapreduce_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.mapreduce_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mapreduce_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mapreduce_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public_rta" {
  count = length(aws_subnet.public_subnets)

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Security Groups
resource "aws_security_group" "mapreduce_sg" {
  name_prefix = "${var.project_name}-sg"
  vpc_id      = aws_vpc.mapreduce_vpc.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MapReduce Dashboard
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # MapReduce RPC
  ingress {
    from_port   = 8000
    to_port     = 8002
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Raft
  ingress {
    from_port   = 1234
    to_port     = 1236
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Metrics
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "mapreduce_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.mapreduce_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "mapreduce_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.mapreduce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "mapreduce_listener" {
  load_balancer_arn = aws_lb.mapreduce_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mapreduce_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "mapreduce_lt" {
  name_prefix   = "${var.project_name}-lt"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.mapreduce_sg.id]

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    s3_bucket = aws_s3_bucket.mapreduce_bucket.bucket
    aws_region = var.aws_region
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.mapreduce_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "mapreduce_asg" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.public_subnets[*].id
  target_group_arns   = [aws_lb_target_group.mapreduce_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_instances
  max_size         = var.max_instances
  desired_capacity = var.desired_instances

  launch_template {
    id      = aws_launch_template.mapreduce_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}

# S3 Bucket
resource "aws_s3_bucket" "mapreduce_bucket" {
  bucket = "${var.project_name}-data-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-data-bucket"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "mapreduce_bucket_versioning" {
  bucket = aws_s3_bucket.mapreduce_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mapreduce_bucket_encryption" {
  bucket = aws_s3_bucket.mapreduce_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role
resource "aws_iam_role" "mapreduce_role" {
  name = "${var.project_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy
resource "aws_iam_role_policy" "mapreduce_policy" {
  name = "${var.project_name}-policy"
  role = aws_iam_role.mapreduce_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mapreduce_bucket.arn,
          "${aws_s3_bucket.mapreduce_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "mapreduce_profile" {
  name = "${var.project_name}-profile"
  role = aws_iam_role.mapreduce_role.name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "mapreduce_logs" {
  name              = "/aws/ec2/${var.project_name}"
  retention_in_days = 7
}
