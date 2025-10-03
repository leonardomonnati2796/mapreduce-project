# S3 Backup Configuration for MapReduce System

# S3 bucket for application data
resource "aws_s3_bucket" "mapreduce_storage" {
  bucket = "${var.project_name}-storage-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "MapReduce Storage"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 bucket for backups
resource "aws_s3_bucket" "mapreduce_backup" {
  bucket = "${var.project_name}-backup-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "MapReduce Backup"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Random ID for bucket suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning for storage
resource "aws_s3_bucket_versioning" "mapreduce_storage_versioning" {
  bucket = aws_s3_bucket.mapreduce_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket versioning for backup
resource "aws_s3_bucket_versioning" "mapreduce_backup_versioning" {
  bucket = aws_s3_bucket.mapreduce_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption for storage
resource "aws_s3_bucket_server_side_encryption_configuration" "mapreduce_storage_encryption" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket encryption for backup
resource "aws_s3_bucket_server_side_encryption_configuration" "mapreduce_backup_encryption" {
  bucket = aws_s3_bucket.mapreduce_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle for storage
resource "aws_s3_bucket_lifecycle_configuration" "mapreduce_storage_lifecycle" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  rule {
    id     = "storage_lifecycle"
    status = "Enabled"

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket lifecycle for backup
resource "aws_s3_bucket_lifecycle_configuration" "mapreduce_backup_lifecycle" {
  bucket = aws_s3_bucket.mapreduce_backup.id

  rule {
    id     = "backup_lifecycle"
    status = "Enabled"

    expiration {
      days = 2555 # 7 years
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# S3 bucket public access block for storage
resource "aws_s3_bucket_public_access_block" "mapreduce_storage_pab" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket public access block for backup
resource "aws_s3_bucket_public_access_block" "mapreduce_backup_pab" {
  bucket = aws_s3_bucket.mapreduce_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets  = true
}

# S3 bucket policy for storage
resource "aws_s3_bucket_policy" "mapreduce_storage_policy" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2Access"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.mapreduce_ec2_role.name}"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.mapreduce_storage.arn}/*"
      },
      {
        Sid       = "AllowBackupAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.mapreduce_backup_role.name}"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.mapreduce_storage.arn}/*"
      }
    ]
  })
}

# S3 bucket policy for backup
resource "aws_s3_bucket_policy" "mapreduce_backup_policy" {
  bucket = aws_s3_bucket.mapreduce_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBackupAccess"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.mapreduce_backup_role.name}"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.mapreduce_backup.arn}/*"
      }
    ]
  })
}

# IAM role for EC2 instances to access S3
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
}

# IAM role for backup Lambda function
resource "aws_iam_role" "mapreduce_backup_role" {
  name = "${var.project_name}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for EC2 S3 access
resource "aws_iam_policy" "mapreduce_ec2_s3_policy" {
  name        = "${var.project_name}-ec2-s3-policy"
  description = "Policy for EC2 instances to access S3"

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
      }
    ]
  })
}

# IAM policy for backup S3 access
resource "aws_iam_policy" "mapreduce_backup_s3_policy" {
  name        = "${var.project_name}-backup-s3-policy"
  description = "Policy for backup Lambda to access S3"

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
          "${aws_s3_bucket.mapreduce_storage.arn}/*",
          aws_s3_bucket.mapreduce_backup.arn,
          "${aws_s3_bucket.mapreduce_backup.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to EC2 role
resource "aws_iam_role_policy_attachment" "mapreduce_ec2_s3_attachment" {
  role       = aws_iam_role.mapreduce_ec2_role.name
  policy_arn = aws_iam_policy.mapreduce_ec2_s3_policy.arn
}

# Attach policy to backup role
resource "aws_iam_role_policy_attachment" "mapreduce_backup_s3_attachment" {
  role       = aws_iam_role.mapreduce_backup_role.name
  policy_arn = aws_iam_policy.mapreduce_backup_s3_policy.arn
}

# Attach basic execution role to EC2
resource "aws_iam_role_policy_attachment" "mapreduce_ec2_basic" {
  role       = aws_iam_role.mapreduce_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# Attach basic execution role to backup
resource "aws_iam_role_policy_attachment" "mapreduce_backup_basic" {
  role       = aws_iam_role.mapreduce_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Instance profile for EC2
resource "aws_iam_instance_profile" "mapreduce_ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.mapreduce_ec2_role.name
}

# CloudWatch Log Group for backup
resource "aws_cloudwatch_log_group" "mapreduce_backup_logs" {
  name              = "/aws/lambda/${var.project_name}-backup"
  retention_in_days = 30
}

# Lambda function for automated backup
resource "aws_lambda_function" "mapreduce_backup" {
  filename         = "lambda-backup.zip"
  function_name    = "${var.project_name}-backup"
  role            = aws_iam_role.mapreduce_backup_role.arn
  handler         = "lambda-backup.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      SOURCE_BUCKET = aws_s3_bucket.mapreduce_storage.bucket
      BACKUP_BUCKET = aws_s3_bucket.mapreduce_backup.bucket
      RETENTION_DAYS = var.backup_retention_days
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.mapreduce_backup_s3_attachment,
    aws_cloudwatch_log_group.mapreduce_backup_logs
  ]
}

# EventBridge rule for scheduled backup
resource "aws_cloudwatch_event_rule" "mapreduce_backup_schedule" {
  name                = "${var.project_name}-backup-schedule"
  description         = "Trigger backup Lambda function"
  schedule_expression = "cron(${var.backup_schedule})"
}

# EventBridge target for backup
resource "aws_cloudwatch_event_target" "mapreduce_backup_target" {
  rule      = aws_cloudwatch_event_rule.mapreduce_backup_schedule.name
  target_id = "MapReduceBackupTarget"
  arn       = aws_lambda_function.mapreduce_backup.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "mapreduce_backup_permission" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mapreduce_backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mapreduce_backup_schedule.arn
}

# S3 bucket notification for real-time backup
resource "aws_s3_bucket_notification" "mapreduce_storage_notification" {
  bucket = aws_s3_bucket.mapreduce_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mapreduce_backup.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "data/"
    filter_suffix       = ".json"
  }
}

# Lambda permission for S3
resource "aws_lambda_permission" "mapreduce_backup_s3_permission" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mapreduce_backup.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.mapreduce_storage.arn
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}