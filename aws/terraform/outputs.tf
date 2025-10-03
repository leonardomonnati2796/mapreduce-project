# Terraform Outputs for MapReduce AWS Deployment

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.mapreduce_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.mapreduce_vpc.cidr_block
}

# Subnet Outputs
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [aws_subnet.mapreduce_public_1.id, aws_subnet.mapreduce_public_2.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [aws_subnet.mapreduce_private_1.id, aws_subnet.mapreduce_private_2.id]
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.mapreduce_alb_sg.id
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.mapreduce_ec2_sg.id
}

# Load Balancer Outputs
output "load_balancer_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.mapreduce_alb.id
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.mapreduce_alb.arn
}

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.mapreduce_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.mapreduce_alb.zone_id
}

# Target Group Outputs
output "target_group_id" {
  description = "ID of the target group"
  value       = aws_lb_target_group.mapreduce_tg.id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.mapreduce_tg.arn
}

# Auto Scaling Group Outputs
output "auto_scaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.mapreduce_asg.id
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.mapreduce_asg.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.mapreduce_asg.arn
}

# Launch Template Outputs
output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.mapreduce_lt.id
}

output "launch_template_arn" {
  description = "ARN of the launch template"
  value       = aws_launch_template.mapreduce_lt.arn
}

# S3 Bucket Outputs
output "s3_bucket_id" {
  description = "ID of the S3 storage bucket"
  value       = aws_s3_bucket.mapreduce_storage.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 storage bucket"
  value       = aws_s3_bucket.mapreduce_storage.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 storage bucket"
  value       = aws_s3_bucket.mapreduce_storage.bucket
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 storage bucket"
  value       = aws_s3_bucket.mapreduce_storage.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 storage bucket"
  value       = aws_s3_bucket.mapreduce_storage.bucket_regional_domain_name
}

output "backup_bucket_id" {
  description = "ID of the S3 backup bucket"
  value       = aws_s3_bucket.mapreduce_backup.id
}

output "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = aws_s3_bucket.mapreduce_backup.arn
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = aws_s3_bucket.mapreduce_backup.bucket
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.mapreduce_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.mapreduce_logs.arn
}

# IAM Outputs
output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.mapreduce_ec2_role.arn
}

output "ec2_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.mapreduce_ec2_profile.arn
}

# Application Outputs
output "application_url" {
  description = "URL of the application"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}"
}

output "dashboard_url" {
  description = "URL of the dashboard"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}/dashboard"
}

output "health_check_url" {
  description = "URL of the health check endpoint"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}/health"
}

output "api_master_url" {
  description = "URL of the master API"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}/api/master"
}

output "api_worker_url" {
  description = "URL of the worker API"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}/api/worker"
}

# Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=MapReduce-System-Dashboard"
}

output "cloudwatch_logs_url" {
  description = "URL of the CloudWatch logs"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups"
}

output "cloudwatch_metrics_url" {
  description = "URL of the CloudWatch metrics"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#metricsV2:"
}

# S3 Outputs
output "s3_console_url" {
  description = "URL of the S3 console"
  value       = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.mapreduce_storage.bucket}"
}

output "backup_console_url" {
  description = "URL of the backup S3 console"
  value       = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.mapreduce_backup.bucket}"
}

# EC2 Outputs
output "ec2_console_url" {
  description = "URL of the EC2 console"
  value       = "https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#Instances:"
}

output "auto_scaling_console_url" {
  description = "URL of the Auto Scaling console"
  value       = "https://console.aws.amazon.com/ec2autoscaling/home?region=${var.aws_region}#/details/${aws_autoscaling_group.mapreduce_asg.name}"
}

# Load Balancer Outputs
output "load_balancer_console_url" {
  description = "URL of the Load Balancer console"
  value       = "https://console.aws.amazon.com/ec2/v2/home?region=${var.aws_region}#LoadBalancers:"
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    region          = var.aws_region
    instance_type   = var.instance_type
    min_instances   = var.min_instances
    max_instances    = var.max_instances
    desired_instances = var.desired_instances
    load_balancer_dns = aws_lb.mapreduce_alb.dns_name
    s3_bucket       = aws_s3_bucket.mapreduce_storage.bucket
    backup_bucket   = aws_s3_bucket.mapreduce_backup.bucket
  }
}

# Connection Information
output "connection_info" {
  description = "Connection information"
  value = {
    ssh_command = "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@<instance-ip>"
    docker_command = "docker run -d --name mapreduce-master -p 8082:8082 mapreduce-master:latest"
    curl_health = "curl -f http://${aws_lb.mapreduce_alb.dns_name}/health"
    curl_dashboard = "curl -f http://${aws_lb.mapreduce_alb.dns_name}/dashboard"
  }
}

# Cost Information
output "cost_info" {
  description = "Cost information"
  value = {
    estimated_monthly_cost = "$${var.instance_type == \"t3.medium\" ? \"~$50-100\" : \"~$100-200\"}"
    cost_optimization_tips = [
      "Use Spot Instances for non-critical workloads",
      "Enable Auto Scaling to scale down during low usage",
      "Use S3 Intelligent Tiering for cost optimization",
      "Monitor CloudWatch costs and set up billing alerts"
    ]
  }
}