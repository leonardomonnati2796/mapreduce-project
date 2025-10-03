# AWS Deployment Guide for MapReduce Project

## Overview

This guide provides comprehensive instructions for deploying the MapReduce system to Amazon Web Services (AWS) using EC2, S3, and Application Load Balancer.

## Architecture

The deployment architecture includes:

- **EC2 Auto Scaling Group**: Automatically scales instances based on load
- **Application Load Balancer (ALB)**: Distributes traffic and provides fault tolerance
- **S3 Storage**: Stores application data and backups
- **CloudWatch**: Monitors metrics and logs
- **IAM Roles**: Manages permissions for AWS services
- **VPC**: Provides network isolation
- **Lambda**: Automates backup tasks

## Prerequisites

Before deploying, ensure you have:

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Installed and configured (`aws configure`)
3. **Terraform**: Version 1.0+ installed
4. **Docker**: Installed and running
5. **SSH Key Pair**: Created in AWS EC2 console

### Install Prerequisites

**AWS CLI:**
```bash
# Linux/macOS
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Windows (PowerShell)
Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "AWSCLIV2.msi"
Start-Process msiexec.exe -ArgumentList "/i AWSCLIV2.msi /quiet" -Wait
```

**Terraform:**
```bash
# Linux/macOS
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Windows (PowerShell)
choco install terraform
```

**Docker:**
```bash
# Linux
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Windows
# Download and install Docker Desktop from https://docker.com
```

## Configuration

### 1. AWS Credentials

Configure AWS credentials:

```bash
aws configure
```

Or set environment variables:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### 2. Environment Configuration

Copy the example configuration file:

```bash
cp aws/config/aws-config.env aws/config/.env
```

Edit `aws/config/.env` with your specific values:

```bash
# AWS Configuration
AWS_REGION=us-east-1
PROJECT_NAME=mapreduce
ENVIRONMENT=prod

# EC2 Configuration
INSTANCE_TYPE=t3.medium
MIN_INSTANCES=2
MAX_INSTANCES=10
DESIRED_INSTANCES=3

# Monitoring
ALARM_EMAIL=your-email@example.com
```

### 3. Terraform Variables

Copy the Terraform variables file:

```bash
cp aws/terraform/terraform.tfvars.example aws/terraform/terraform.tfvars
```

Edit `aws/terraform/terraform.tfvars` with your specific values.

### 4. Create EC2 Key Pair

Create a new key pair for SSH access:

```bash
aws ec2 create-key-pair --key-name mapreduce-key-pair --query 'KeyMaterial' --output text > ~/.ssh/mapreduce-key-pair.pem
chmod 400 ~/.ssh/mapreduce-key-pair.pem
```

## Deployment

### Option 1: Automated Setup (Recommended)

Use the automated setup script:

**Linux/macOS:**
```bash
chmod +x aws/scripts/setup-aws-env.sh
./aws/scripts/setup-aws-env.sh
```

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File aws/scripts/setup-aws-env.ps1
```

Then deploy:

**Linux/macOS:**
```bash
chmod +x aws/scripts/deploy-aws.sh
./aws/scripts/deploy-aws.sh
```

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File aws/scripts/deploy-aws.ps1
```

### Option 2: Using Makefile

Use the provided Makefile for easy deployment:

```bash
# Full deployment
make -f Makefile.aws aws-full-deploy

# Quick deployment (skip some steps)
make -f Makefile.aws aws-quick-deploy

# Custom configuration
make -f Makefile.aws aws-deploy AWS_REGION=us-west-2 INSTANCE_TYPE=t3.large
```

### Option 3: Manual Terraform Deployment

Step-by-step manual deployment:

1. **Initialize Terraform:**
   ```bash
   cd aws/terraform
   terraform init
   ```

2. **Validate Configuration:**
   ```bash
   terraform validate
   ```

3. **Create Plan:**
   ```bash
   terraform plan -out=tfplan
   ```

4. **Apply Configuration:**
   ```bash
   terraform apply tfplan
   ```

5. **Get Outputs:**
   ```bash
   terraform output
   ```

## Docker Images

### Build Docker Images

Build the required Docker images:

```bash
# Build all images
docker build -f docker/Dockerfile.aws -t mapreduce-master:latest --build-arg BUILD_TARGET=master .
docker build -f docker/Dockerfile.aws -t mapreduce-worker:latest --build-arg BUILD_TARGET=worker .
docker build -f docker/Dockerfile.aws -t mapreduce-backup:latest --build-arg BUILD_TARGET=backup .
```

### Push to Docker Registry (Optional)

If using a private Docker registry:

```bash
# Tag images
docker tag mapreduce-master:latest your-registry/mapreduce-master:latest
docker tag mapreduce-worker:latest your-registry/mapreduce-worker:latest
docker tag mapreduce-backup:latest your-registry/mapreduce-backup:latest

# Push images
docker push your-registry/mapreduce-master:latest
docker push your-registry/mapreduce-worker:latest
docker push your-registry/mapreduce-backup:latest
```

## Accessing the Application

After successful deployment, access the application using the Load Balancer DNS name:

```bash
# Get Load Balancer DNS
cd aws/terraform
terraform output load_balancer_dns_name
```

### Application URLs

- **Dashboard:** `http://<load-balancer-dns>/dashboard`
- **Health Check:** `http://<load-balancer-dns>/health`
- **Master API:** `http://<load-balancer-dns>/api/master`
- **Worker API:** `http://<load-balancer-dns>/api/worker`

### Example

```bash
LB_DNS=$(cd aws/terraform && terraform output -raw load_balancer_dns_name)
echo "Dashboard: http://$LB_DNS/dashboard"
echo "Health: http://$LB_DNS/health"

# Test health endpoint
curl http://$LB_DNS/health
```

## Monitoring

### CloudWatch Logs

View logs in CloudWatch:

```bash
# List log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/ec2/mapreduce"

# Tail logs
aws logs tail /aws/ec2/mapreduce/master --follow
```

### CloudWatch Metrics

View metrics in the AWS Console:

- Navigate to CloudWatch > Dashboards
- Select "MapReduce-System-Dashboard"
- View CPU, memory, and application metrics

### Alarms

Configure email notifications:

1. Go to CloudWatch > Alarms
2. Subscribe to the SNS topic created by Terraform
3. Confirm the email subscription

## Backup and Recovery

### S3 Backup

Backups are automated using Lambda functions:

- **Schedule:** Daily at 2:00 AM UTC (configurable)
- **Retention:** 30 days (configurable)
- **Location:** S3 backup bucket

### Manual Backup

Create a manual backup:

```bash
# Get bucket names
cd aws/terraform
STORAGE_BUCKET=$(terraform output -raw s3_bucket_name)
BACKUP_BUCKET=$(terraform output -raw backup_bucket_name)

# Create backup
aws s3 sync s3://$STORAGE_BUCKET s3://$BACKUP_BUCKET/backup/$(date +%Y%m%d_%H%M%S)
```

### Restore from Backup

Restore data from a backup:

```bash
# List backups
aws s3 ls s3://$BACKUP_BUCKET/backup/

# Restore specific backup
aws s3 sync s3://$BACKUP_BUCKET/backup/20240101_020000 s3://$STORAGE_BUCKET
```

## Scaling

### Manual Scaling

Adjust the number of instances:

```bash
# Update desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name mapreduce-asg \
  --desired-capacity 5

# Update min/max size
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name mapreduce-asg \
  --min-size 2 \
  --max-size 15
```

### Auto Scaling

Auto scaling is configured based on:

- **CPU Utilization:** Scale up at 70%, scale down at 20%
- **Memory Utilization:** Scale up at 80%
- **Cooldown Period:** 5 minutes

## Troubleshooting

### Common Issues

**Issue: Instances not healthy**

```bash
# Check instance status
aws ec2 describe-instance-status --instance-ids <instance-id>

# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# SSH into instance
ssh -i ~/.ssh/mapreduce-key-pair.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo tail -f /var/log/mapreduce/master.log
```

**Issue: Load Balancer not accessible**

```bash
# Check security groups
aws ec2 describe-security-groups --group-ids <security-group-id>

# Check listener configuration
aws elbv2 describe-listeners --load-balancer-arn <load-balancer-arn>

# Test from local machine
curl -v http://<load-balancer-dns>/health
```

**Issue: Terraform errors**

```bash
# Refresh state
terraform refresh

# Force unlock (if locked)
terraform force-unlock <lock-id>

# Re-initialize
rm -rf .terraform
terraform init
```

### Debug Mode

Enable debug mode for more verbose output:

```bash
export TF_LOG=DEBUG
terraform apply
```

## Cleanup

### Remove All Resources

**Using Makefile:**
```bash
make -f Makefile.aws aws-full-cleanup
```

**Using Terraform:**
```bash
cd aws/terraform
terraform destroy -auto-approve
```

**Using Script:**
```bash
# Linux/macOS
./aws/scripts/deploy-aws.sh --cleanup

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File aws/scripts/deploy-aws.ps1 -Cleanup
```

### Manual Cleanup

If automated cleanup fails:

```bash
# Delete Auto Scaling Group
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name mapreduce-asg --force-delete

# Delete Load Balancer
aws elbv2 delete-load-balancer --load-balancer-arn <load-balancer-arn>

# Delete Target Group
aws elbv2 delete-target-group --target-group-arn <target-group-arn>

# Delete S3 buckets
aws s3 rb s3://<storage-bucket> --force
aws s3 rb s3://<backup-bucket> --force

# Delete VPC resources
# (Requires deleting all resources in VPC first)
```

## Cost Optimization

### Estimated Costs

Based on default configuration (us-east-1):

- **EC2 (3x t3.medium):** ~$75/month
- **ALB:** ~$20/month
- **S3 Storage:** ~$5/month (100GB)
- **CloudWatch:** ~$5/month
- **Data Transfer:** Variable

**Total:** ~$105-150/month

### Cost Saving Tips

1. **Use Spot Instances:** Save up to 90% on EC2 costs
2. **Right-size Instances:** Monitor usage and adjust instance types
3. **S3 Lifecycle Policies:** Automatically transition to cheaper storage classes
4. **Reserved Instances:** Save up to 75% with 1-3 year commitments
5. **Auto Scaling:** Scale down during low usage periods
6. **CloudWatch Optimization:** Reduce log retention and metrics frequency

## Security Best Practices

1. **Restrict SSH Access:** Update `ssh_cidr_blocks` to your IP only
2. **Enable HTTPS:** Configure SSL certificate for ALB
3. **Enable S3 Encryption:** Already enabled by default
4. **IAM Roles:** Use least privilege principle
5. **Network Isolation:** Use private subnets for EC2 instances
6. **Security Groups:** Review and tighten security group rules
7. **Regular Updates:** Keep AMIs and Docker images updated
8. **Enable CloudTrail:** Audit all AWS API calls
9. **Enable GuardDuty:** Detect security threats
10. **Backup Encryption:** Already enabled by default

## Support

For issues or questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review AWS CloudWatch logs
3. Check Terraform plan output
4. Review security group rules
5. Verify IAM permissions

## References

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Docker Documentation](https://docs.docker.com/)

## License

This deployment configuration is part of the MapReduce project. See the main README for license information.