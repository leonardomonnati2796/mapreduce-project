# Terraform Variables for MapReduce AWS Deployment

# AWS Configuration
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
  default     = ""
}

# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "mapreduce"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "version" {
  description = "Version of the application"
  type        = string
  default     = "1.0.0"
}

# GitHub Repository (for build on EC2)
variable "repo_url" {
  description = "Git repository URL containing the application source"
  type        = string
  default     = ""
}

variable "repo_branch" {
  description = "Git branch to checkout on EC2"
  type        = string
  default     = "main"
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 2
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "desired_instances" {
  description = "Desired number of instances"
  type        = number
  default     = 3
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair"
  type        = string
  default     = "mapreduce-key-pair"
}

# Load Balancer Configuration
variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default     = "mapreduce-alb"
}

variable "alb_scheme" {
  description = "Scheme of the Application Load Balancer"
  type        = string
  default     = "internet-facing"
}

variable "alb_type" {
  description = "Type of the Application Load Balancer"
  type        = string
  default     = "application"
}

variable "alb_ip_address_type" {
  description = "IP address type of the Application Load Balancer"
  type        = string
  default     = "ipv4"
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for storage"
  type        = string
  default     = "mapreduce-storage"
}

variable "s3_backup_bucket" {
  description = "Name of the S3 bucket for backup"
  type        = string
  default     = "mapreduce-backup"
}

variable "s3_terraform_bucket" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "mapreduce-terraform-state"
}

# Database Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine" {
  description = "RDS engine"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "13.7"
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "mapreduce"
}

variable "db_username" {
  description = "RDS username"
  type        = string
  default     = "mapreduce"
}

variable "db_password" {
  description = "RDS password"
  type        = string
  default     = ""
  sensitive   = true
}

# Monitoring Configuration
variable "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  type        = string
  default     = "/aws/ec2/mapreduce"
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email for CloudWatch alarms"
  type        = string
  default     = "admin@example.com"
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "http_cidr_blocks" {
  description = "CIDR blocks allowed for HTTP access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "https_cidr_blocks" {
  description = "CIDR blocks allowed for HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Application Configuration
variable "app_port" {
  description = "Application port"
  type        = number
  default     = 8080
}

variable "dashboard_port" {
  description = "Dashboard port"
  type        = number
  default     = 3000
}

variable "worker_port" {
  description = "Worker port"
  type        = number
  default     = 8081
}

variable "master_port" {
  description = "Master port"
  type        = number
  default     = 8082
}

# Docker Configuration
variable "docker_registry" {
  description = "Docker registry URL"
  type        = string
  default     = ""
}

variable "docker_image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "docker_compose_file" {
  description = "Docker Compose file name"
  type        = string
  default     = "docker-compose.aws.yml"
}

# Backup Configuration
variable "backup_schedule" {
  description = "Backup schedule (cron expression)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 30
}

variable "backup_encryption" {
  description = "Enable backup encryption"
  type        = bool
  default     = true
}

# Auto Scaling Configuration
variable "scale_up_cooldown" {
  description = "Scale up cooldown period in seconds"
  type        = number
  default     = 300
}

variable "scale_down_cooldown" {
  description = "Scale down cooldown period in seconds"
  type        = number
  default     = 300
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization percentage"
  type        = number
  default     = 70
}

variable "target_memory_utilization" {
  description = "Target memory utilization percentage"
  type        = number
  default     = 80
}

# Health Check Configuration
variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_threshold" {
  description = "Health check threshold"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Health check unhealthy threshold"
  type        = number
  default     = 3
}

# Logging Configuration
variable "log_level" {
  description = "Log level"
  type        = string
  default     = "info"
}

variable "log_format" {
  description = "Log format"
  type        = string
  default     = "json"
}

variable "log_output" {
  description = "Log output"
  type        = string
  default     = "stdout"
}

# Performance Configuration
variable "worker_threads" {
  description = "Number of worker threads"
  type        = number
  default     = 4
}

variable "max_connections" {
  description = "Maximum number of connections"
  type        = number
  default     = 1000
}

variable "connection_timeout" {
  description = "Connection timeout in seconds"
  type        = number
  default     = 30
}

variable "read_timeout" {
  description = "Read timeout in seconds"
  type        = number
  default     = 60
}

variable "write_timeout" {
  description = "Write timeout in seconds"
  type        = number
  default     = 60
}

# Security Headers
variable "security_headers" {
  description = "Enable security headers"
  type        = bool
  default     = true
}

variable "cors_origins" {
  description = "CORS origins"
  type        = string
  default     = "*"
}

variable "cors_methods" {
  description = "CORS methods"
  type        = string
  default     = "GET,POST,PUT,DELETE,OPTIONS"
}

variable "cors_headers" {
  description = "CORS headers"
  type        = string
  default     = "Content-Type,Authorization"
}

# Rate Limiting
variable "rate_limit_enabled" {
  description = "Enable rate limiting"
  type        = bool
  default     = true
}

variable "rate_limit_requests" {
  description = "Rate limit requests per window"
  type        = number
  default     = 100
}

variable "rate_limit_window" {
  description = "Rate limit window in seconds"
  type        = number
  default     = 60
}

# SSL/TLS Configuration
variable "ssl_enabled" {
  description = "Enable SSL/TLS"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN"
  type        = string
  default     = ""
}

variable "ssl_policy" {
  description = "SSL policy"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2017-01"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr_1" {
  description = "Public subnet 1 CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_cidr_2" {
  description = "Public subnet 2 CIDR block"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidr_1" {
  description = "Private subnet 1 CIDR block"
  type        = string
  default     = "10.0.10.0/24"
}

variable "private_subnet_cidr_2" {
  description = "Private subnet 2 CIDR block"
  type        = string
  default     = "10.0.20.0/24"
}

# Availability Zones
variable "az_1" {
  description = "Availability zone 1"
  type        = string
  default     = "us-east-1a"
}

variable "az_2" {
  description = "Availability zone 2"
  type        = string
  default     = "us-east-1b"
}

# Tags
variable "tag_environment" {
  description = "Environment tag"
  type        = string
  default     = "production"
}

variable "tag_project" {
  description = "Project tag"
  type        = string
  default     = "mapreduce"
}

variable "tag_owner" {
  description = "Owner tag"
  type        = string
  default     = "devops"
}

variable "tag_cost_center" {
  description = "Cost center tag"
  type        = string
  default     = "engineering"
}