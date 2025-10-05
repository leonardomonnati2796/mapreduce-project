# AWS Infrastructure for MapReduce Deployment
# This file contains the main infrastructure configuration

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "mapreduce_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "mapreduce_igw" {
  vpc_id = aws_vpc.mapreduce_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Public Subnets
resource "aws_subnet" "mapreduce_public_1" {
  vpc_id                  = aws_vpc.mapreduce_vpc.id
  cidr_block              = var.public_subnet_cidr_1
  availability_zone       = var.az_1
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-1"
    Environment = var.environment
    Project     = var.project_name
    Type        = "public"
  }
}

resource "aws_subnet" "mapreduce_public_2" {
  vpc_id                  = aws_vpc.mapreduce_vpc.id
  cidr_block              = var.public_subnet_cidr_2
  availability_zone       = var.az_2
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-2"
    Environment = var.environment
    Project     = var.project_name
    Type        = "public"
  }
}

# Private Subnets
resource "aws_subnet" "mapreduce_private_1" {
  vpc_id            = aws_vpc.mapreduce_vpc.id
  cidr_block        = var.private_subnet_cidr_1
  availability_zone = var.az_1

  tags = {
    Name        = "${var.project_name}-private-1"
    Environment = var.environment
    Project     = var.project_name
    Type        = "private"
  }
}

resource "aws_subnet" "mapreduce_private_2" {
  vpc_id            = aws_vpc.mapreduce_vpc.id
  cidr_block        = var.private_subnet_cidr_2
  availability_zone = var.az_2

  tags = {
    Name        = "${var.project_name}-private-2"
    Environment = var.environment
    Project     = var.project_name
    Type        = "private"
  }
}

# Route Tables
resource "aws_route_table" "mapreduce_public_rt" {
  vpc_id = aws_vpc.mapreduce_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mapreduce_igw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "mapreduce_private_rt" {
  vpc_id = aws_vpc.mapreduce_vpc.id

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Table Associations
resource "aws_route_table_association" "mapreduce_public_1_rta" {
  subnet_id      = aws_subnet.mapreduce_public_1.id
  route_table_id = aws_route_table.mapreduce_public_rt.id
}

resource "aws_route_table_association" "mapreduce_public_2_rta" {
  subnet_id      = aws_subnet.mapreduce_public_2.id
  route_table_id = aws_route_table.mapreduce_public_rt.id
}

resource "aws_route_table_association" "mapreduce_private_1_rta" {
  subnet_id      = aws_subnet.mapreduce_private_1.id
  route_table_id = aws_route_table.mapreduce_private_rt.id
}

resource "aws_route_table_association" "mapreduce_private_2_rta" {
  subnet_id      = aws_subnet.mapreduce_private_2.id
  route_table_id = aws_route_table.mapreduce_private_rt.id
}

# Security Groups
resource "aws_security_group" "mapreduce_alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.mapreduce_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.https_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-alb-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "mapreduce_ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.mapreduce_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    description = "Application Port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  ingress {
    description = "Dashboard Port"
    from_port   = var.dashboard_port
    to_port     = var.dashboard_port
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  ingress {
    description = "Worker Port"
    from_port   = var.worker_port
    to_port     = var.worker_port
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  ingress {
    description = "Master Port"
    from_port   = var.master_port
    to_port     = var.master_port
    protocol    = "tcp"
    security_groups = [aws_security_group.mapreduce_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-ec2-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Application Load Balancer
resource "aws_lb" "mapreduce_alb" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = var.alb_type
  security_groups    = [aws_security_group.mapreduce_alb_sg.id]
  subnets            = [aws_subnet.mapreduce_public_1.id, aws_subnet.mapreduce_public_2.id]

  enable_deletion_protection = false

  tags = {
    Name        = var.alb_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# Target Group
resource "aws_lb_target_group" "mapreduce_tg" {
  name     = "${var.project_name}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.mapreduce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name        = "${var.project_name}-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Load Balancer Listener
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
resource "aws_launch_template" "mapreduce_master_lt" {
  name_prefix   = "${var.project_name}-master-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.mapreduce_ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.mapreduce_ec2_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    AWS_REGION     = var.aws_region,
    S3_BUCKET      = aws_s3_bucket.mapreduce_storage.bucket,
    LOG_GROUP_NAME = aws_cloudwatch_log_group.mapreduce_logs.name,
    REPO_URL       = var.repo_url,
    REPO_BRANCH    = var.repo_branch
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-instance"
      Environment = var.environment
      Project     = var.project_name
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name           = "${var.project_name}-master"
      Environment    = var.environment
      Project        = var.project_name
      ${var.instance_role_tag_key} = "MASTER"
    }
  }

  tags = {
    Name        = "${var.project_name}-master-lt"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Launch Template for workers
resource "aws_launch_template" "mapreduce_worker_lt" {
  name_prefix   = "${var.project_name}-worker-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.mapreduce_ec2_sg.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.mapreduce_ec2_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    AWS_REGION     = var.aws_region,
    S3_BUCKET      = aws_s3_bucket.mapreduce_storage.bucket,
    LOG_GROUP_NAME = aws_cloudwatch_log_group.mapreduce_logs.name,
    REPO_URL       = var.repo_url,
    REPO_BRANCH    = var.repo_branch
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name           = "${var.project_name}-worker"
      Environment    = var.environment
      Project        = var.project_name
      ${var.instance_role_tag_key} = "WORKER"
    }
  }

  tags = {
    Name        = "${var.project_name}-worker-lt"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Auto Scaling Group - Masters
resource "aws_autoscaling_group" "mapreduce_masters_asg" {
  name                = "${var.project_name}-masters-asg"
  vpc_zone_identifier = [aws_subnet.mapreduce_public_1.id, aws_subnet.mapreduce_public_2.id]
  target_group_arns   = [aws_lb_target_group.mapreduce_master_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.masters_min
  max_size         = var.masters_max
  desired_capacity = var.masters_desired

  launch_template {
    id      = aws_launch_template.mapreduce_master_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# Auto Scaling Group - Workers
resource "aws_autoscaling_group" "mapreduce_workers_asg" {
  name                = "${var.project_name}-workers-asg"
  vpc_zone_identifier = [aws_subnet.mapreduce_public_1.id, aws_subnet.mapreduce_public_2.id]
  target_group_arns   = [aws_lb_target_group.mapreduce_worker_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.workers_min
  max_size         = var.workers_max
  desired_capacity = var.workers_desired

  launch_template {
    id      = aws_launch_template.mapreduce_worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-worker-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "mapreduce_scale_up" {
  name                   = "${var.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scale_up_cooldown
  autoscaling_group_name = aws_autoscaling_group.mapreduce_asg.name
}

resource "aws_autoscaling_policy" "mapreduce_scale_down" {
  name                   = "${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scale_down_cooldown
  autoscaling_group_name = aws_autoscaling_group.mapreduce_asg.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "mapreduce_cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.target_cpu_utilization
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.mapreduce_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.mapreduce_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "mapreduce_cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.mapreduce_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.mapreduce_asg.name
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "mapreduce_logs" {
  name              = var.cloudwatch_log_group
  retention_in_days = var.cloudwatch_retention_days

  tags = {
    Name        = "${var.project_name}-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "mapreduce_ec2_role" {
  name = "${var.project_name}-ec2-role"

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

  tags = {
    Name        = "${var.project_name}-ec2-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM Policy for EC2 instances
resource "aws_iam_policy" "mapreduce_ec2_policy" {
  name        = "${var.project_name}-ec2-policy"
  description = "Policy for MapReduce EC2 instances"

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
          aws_s3_bucket.mapreduce_storage.arn,
          "${aws_s3_bucket.mapreduce_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.mapreduce_logs.arn}:*"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "mapreduce_ec2_policy_attachment" {
  role       = aws_iam_role.mapreduce_ec2_role.name
  policy_arn = aws_iam_policy.mapreduce_ec2_policy.arn
}

# Attach basic execution role
resource "aws_iam_role_policy_attachment" "mapreduce_ec2_basic" {
  role       = aws_iam_role.mapreduce_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# Instance Profile
resource "aws_iam_instance_profile" "mapreduce_ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.mapreduce_ec2_role.name

  tags = {
    Name        = "${var.project_name}-ec2-profile"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 Bucket for MapReduce Storage
resource "aws_s3_bucket" "mapreduce_storage" {
  bucket = var.s3_bucket_name

  tags = {
    Name        = "${var.project_name}-storage"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "mapreduce_storage_versioning" {
  bucket = aws_s3_bucket.mapreduce_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "mapreduce_storage_lifecycle" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  rule {
    id     = "mapreduce_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "mapreduce_storage_encryption" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "mapreduce_storage_pab" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enhanced Load Balancer with Multiple Target Groups
resource "aws_lb_target_group" "mapreduce_dashboard_tg" {
  name     = "${var.project_name}-dashboard-tg"
  port     = var.dashboard_port
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
    Name        = "${var.project_name}-dashboard-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "mapreduce_master_tg" {
  name     = "${var.project_name}-master-tg"
  port     = var.master_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.mapreduce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name        = "${var.project_name}-master-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lb_target_group" "mapreduce_worker_tg" {
  name     = "${var.project_name}-worker-tg"
  port     = var.worker_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.mapreduce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name        = "${var.project_name}-worker-tg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Load Balancer Listeners with Path-based Routing
resource "aws_lb_listener_rule" "mapreduce_dashboard_rule" {
  listener_arn = aws_lb_listener.mapreduce_listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mapreduce_dashboard_tg.arn
  }

  condition {
    path_pattern {
      values = ["/dashboard*", "/health*", "/metrics*", "/jobs*", "/workers*", "/output*"]
    }
  }
}

resource "aws_lb_listener_rule" "mapreduce_master_rule" {
  listener_arn = aws_lb_listener.mapreduce_listener.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mapreduce_master_tg.arn
  }

  condition {
    path_pattern {
      values = ["/master*", "/api/master*"]
    }
  }
}

resource "aws_lb_listener_rule" "mapreduce_worker_rule" {
  listener_arn = aws_lb_listener.mapreduce_listener.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mapreduce_worker_tg.arn
  }

  condition {
    path_pattern {
      values = ["/worker*", "/api/worker*"]
    }
  }
}

# CloudWatch Alarms for Load Balancer
resource "aws_cloudwatch_metric_alarm" "mapreduce_alb_high_latency" {
  alarm_name          = "${var.project_name}-alb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "This metric monitors alb response time"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.mapreduce_alb.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "mapreduce_alb_high_5xx" {
  alarm_name          = "${var.project_name}-alb-high-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors alb 5xx errors"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.mapreduce_alb.arn_suffix
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "mapreduce_alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Data source for Amazon Linux AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}