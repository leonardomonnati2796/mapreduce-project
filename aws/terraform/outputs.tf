output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.mapreduce_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.mapreduce_sg.id
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.mapreduce_alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.mapreduce_alb.zone_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.mapreduce_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.mapreduce_bucket.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.mapreduce_role.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.mapreduce_logs.name
}

output "dashboard_url" {
  description = "URL to access the MapReduce dashboard"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}"
}

output "health_check_url" {
  description = "URL for health checks"
  value       = "http://${aws_lb.mapreduce_alb.dns_name}/health"
}
