# AWS Quickstart Guide

Get your MapReduce system running on AWS in 5 minutes!

## Prerequisites

✅ AWS Account  
✅ AWS CLI configured (`aws configure`)  
✅ Terraform installed  
✅ Docker installed  

## Quick Deploy

### Step 1: Configure AWS

```bash
# Configure AWS credentials
aws configure

# Or set environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### Step 2: Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name mapreduce-key-pair \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/mapreduce-key-pair.pem

chmod 400 ~/.ssh/mapreduce-key-pair.pem
```

### Step 3: Setup Environment

```bash
# Linux/macOS
chmod +x aws/scripts/setup-aws-env.sh
./aws/scripts/setup-aws-env.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File aws/scripts/setup-aws-env.ps1
```

### Step 4: Deploy

```bash
# Linux/macOS
chmod +x aws/scripts/deploy-aws.sh
./aws/scripts/deploy-aws.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File aws/scripts/deploy-aws.ps1
```

### Step 5: Access Your Application

```bash
# Get Load Balancer DNS
cd aws/terraform
LB_DNS=$(terraform output -raw load_balancer_dns_name)

# Open dashboard
echo "Dashboard: http://$LB_DNS/dashboard"

# Test health endpoint
curl http://$LB_DNS/health
```

## Using Makefile (Alternative)

```bash
# Full deployment
make -f Makefile.aws aws-full-deploy

# Check status
make -f Makefile.aws aws-status

# View logs
make -f Makefile.aws aws-logs
```

## Configuration Options

Customize your deployment:

```bash
# Deploy with custom settings
./aws/scripts/deploy-aws.sh \
  --region us-west-2 \
  --instance-type t3.large \
  --min-instances 3 \
  --max-instances 15 \
  --desired-instances 5
```

Or use Makefile:

```bash
make -f Makefile.aws aws-deploy \
  AWS_REGION=us-west-2 \
  INSTANCE_TYPE=t3.large \
  MIN_INSTANCES=3 \
  MAX_INSTANCES=15 \
  DESIRED_INSTANCES=5
```

## Application URLs

After deployment, your application will be available at:

- **Dashboard:** `http://<load-balancer-dns>/dashboard`
- **Health Check:** `http://<load-balancer-dns>/health`
- **Master API:** `http://<load-balancer-dns>/api/master`
- **Worker API:** `http://<load-balancer-dns>/api/worker`

## Monitoring

### CloudWatch Logs

```bash
# View master logs
aws logs tail /aws/ec2/mapreduce/master --follow

# View worker logs
aws logs tail /aws/ec2/mapreduce/worker --follow
```

### CloudWatch Dashboard

Navigate to: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=MapReduce-System-Dashboard

### Check Status

```bash
make -f Makefile.aws aws-status
```

## Scaling

```bash
# Scale up
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name mapreduce-asg \
  --desired-capacity 10

# Scale down
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name mapreduce-asg \
  --desired-capacity 2
```

## Backup

Backups are automated daily at 2:00 AM UTC.

### Manual Backup

```bash
make -f Makefile.aws aws-s3-backup
```

### View Backups

```bash
make -f Makefile.aws aws-s3-status
```

## Cleanup

Remove all AWS resources:

```bash
# Using Makefile
make -f Makefile.aws aws-full-cleanup

# Using Terraform
cd aws/terraform
terraform destroy -auto-approve
```

## Troubleshooting

### Deployment Failed

```bash
# Check Terraform state
cd aws/terraform
terraform show

# Check AWS resources
make -f Makefile.aws aws-status

# View logs
make -f Makefile.aws aws-logs
```

### Application Not Accessible

```bash
# Check Load Balancer status
aws elbv2 describe-load-balancers | grep mapreduce

# Check target health
aws elbv2 describe-target-health --target-group-arn <arn>

# SSH into instance
ssh -i ~/.ssh/mapreduce-key-pair.pem ec2-user@<instance-ip>

# Check logs
sudo tail -f /var/log/user-data.log
sudo tail -f /var/log/mapreduce/master.log
```

### Auto Scaling Not Working

```bash
# Check Auto Scaling Group
aws autoscaling describe-auto-scaling-groups | grep mapreduce

# Check scaling policies
aws autoscaling describe-policies | grep mapreduce

# Check CloudWatch alarms
aws cloudwatch describe-alarms | grep mapreduce
```

## Cost Estimate

**Estimated Monthly Cost** (default configuration):

- EC2 (3x t3.medium): ~$75
- Application Load Balancer: ~$20
- S3 Storage (100GB): ~$5
- CloudWatch: ~$5
- **Total: ~$105-150/month**

### Cost Optimization

1. Use t3.micro for development: ~$7/month per instance
2. Enable Auto Scaling to scale down during low usage
3. Use Spot Instances for up to 90% savings
4. Enable S3 Intelligent Tiering

## Next Steps

1. ✅ Configure SSL certificate for HTTPS
2. ✅ Set up custom domain name
3. ✅ Enable CloudTrail for audit logs
4. ✅ Configure backup notifications
5. ✅ Set up monitoring alerts
6. ✅ Review security groups

## Support

For detailed documentation, see [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md)

## Quick Reference

```bash
# Setup
./aws/scripts/setup-aws-env.sh

# Deploy
./aws/scripts/deploy-aws.sh

# Status
make -f Makefile.aws aws-status

# Logs
make -f Makefile.aws aws-logs

# Backup
make -f Makefile.aws aws-s3-backup

# Cleanup
make -f Makefile.aws aws-full-cleanup
```

## Configuration Files

- **Environment:** `aws/config/.env`
- **Terraform:** `aws/terraform/terraform.tfvars`
- **Docker:** `aws/docker/docker-compose.production.yml`
- **Nginx:** `aws/docker/nginx.conf`

## Important Notes

- ⚠️ Always backup before making changes
- ⚠️ Review costs in AWS Cost Explorer
- ⚠️ Keep AWS credentials secure
- ⚠️ Enable MFA on your AWS account
- ⚠️ Regularly update Docker images and AMIs