# CloudWatch Alarms for MapReduce System

# CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "mapreduce-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.mapreduce_asg.name
  }
}

# Memory Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  alarm_name          = "mapreduce-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ec2 memory utilization"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.mapreduce_asg.name
  }
}

# Disk Space Alarm
resource "aws_cloudwatch_metric_alarm" "high_disk_utilization" {
  alarm_name          = "mapreduce-high-disk-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DiskSpaceUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This metric monitors ec2 disk space utilization"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.mapreduce_asg.name
  }
}

# Application Health Check Alarm
resource "aws_cloudwatch_metric_alarm" "application_health_check" {
  alarm_name          = "mapreduce-application-health-check"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors application health"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.mapreduce_tg.arn_suffix
    LoadBalancer = aws_lb.mapreduce_alb.arn_suffix
  }
}

# Load Balancer Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "mapreduce-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "5"
  alarm_description   = "This metric monitors load balancer response time"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.mapreduce_alb.arn_suffix
  }
}

# Load Balancer Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "mapreduce-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors load balancer error rate"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.mapreduce_alb.arn_suffix
  }
}

# S3 Bucket Size Alarm
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "mapreduce-s3-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = aws_s3_bucket.mapreduce_storage.bucket
    StorageType = "StandardStorage"
  }
}

# S3 Number of Objects Alarm
resource "aws_cloudwatch_metric_alarm" "s3_number_of_objects" {
  alarm_name          = "mapreduce-s3-number-of-objects"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = "86400"
  statistic           = "Average"
  threshold           = "10000"
  alarm_description   = "This metric monitors S3 number of objects"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = aws_s3_bucket.mapreduce_storage.bucket
    StorageType = "AllStorageTypes"
  }
}

# Custom Application Metrics
resource "aws_cloudwatch_metric_alarm" "mapreduce_job_failure_rate" {
  alarm_name          = "mapreduce-job-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "JobFailureRate"
  namespace           = "MapReduce/Application"
  period              = "300"
  statistic           = "Average"
  threshold           = "0.1" # 10% failure rate
  alarm_description   = "This metric monitors MapReduce job failure rate"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "mapreduce_worker_count" {
  alarm_name          = "mapreduce-worker-count"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WorkerCount"
  namespace           = "MapReduce/Application"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors MapReduce worker count"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"
}

resource "aws_cloudwatch_metric_alarm" "mapreduce_master_health" {
  alarm_name          = "mapreduce-master-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MasterHealth"
  namespace           = "MapReduce/Application"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors MapReduce master health"
  alarm_actions       = [aws_sns_topic.mapreduce_alerts.arn]
  ok_actions          = [aws_sns_topic.mapreduce_alerts.arn]
  treat_missing_data  = "breaching"
}

# SNS Topic for Alerts
resource "aws_sns_topic" "mapreduce_alerts" {
  name = "mapreduce-alerts"
}

resource "aws_sns_topic_subscription" "mapreduce_alerts_email" {
  topic_arn = aws_sns_topic.mapreduce_alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "mapreduce_dashboard" {
  dashboard_name = "MapReduce-System-Dashboard"

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
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.mapreduce_asg.name],
            [".", "MemoryUtilization", ".", "."],
            [".", "DiskSpaceUtilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "EC2 Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.mapreduce_alb.arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Load Balancer Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.mapreduce_storage.bucket, "StorageType", "StandardStorage"],
            [".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "S3 Storage Metrics"
          period  = 86400
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["MapReduce/Application", "JobFailureRate"],
            [".", "WorkerCount"],
            [".", "MasterHealth"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Application Metrics"
          period  = 300
        }
      }
    ]
  })
}