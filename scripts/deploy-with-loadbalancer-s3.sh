#!/bin/bash

# Deploy MapReduce with Load Balancer and S3 Integration
# This script deploys the MapReduce system with enhanced fault tolerance and S3 storage

set -e

echo "🚀 Deploying MapReduce with Load Balancer and S3 Integration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="mapreduce"
ENVIRONMENT="production"
AWS_REGION="us-east-1"
S3_BUCKET="mapreduce-storage-$(date +%s)"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "  Project: $PROJECT_NAME"
echo "  Environment: $ENVIRONMENT"
echo "  AWS Region: $AWS_REGION"
echo "  S3 Bucket: $S3_BUCKET"

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI first.${NC}"
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install Terraform first.${NC}"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites found${NC}"

# Set up AWS credentials
echo -e "${BLUE}🔐 Setting up AWS credentials...${NC}"
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}⚠️  AWS credentials not set. Please configure AWS CLI:${NC}"
    echo "  aws configure"
    echo "  or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables"
    exit 1
fi

# Create S3 bucket for Terraform state
echo -e "${BLUE}🪣 Creating S3 bucket for Terraform state...${NC}"
TERRAFORM_BUCKET="mapreduce-terraform-state-$(date +%s)"
aws s3 mb s3://$TERRAFORM_BUCKET --region $AWS_REGION || echo "Bucket may already exist"

# Initialize Terraform
echo -e "${BLUE}🏗️  Initializing Terraform...${NC}"
cd aws/terraform

# Create terraform.tfvars
cat > terraform.tfvars << EOF
aws_region = "$AWS_REGION"
project_name = "$PROJECT_NAME"
environment = "$ENVIRONMENT"
s3_bucket_name = "$S3_BUCKET"
s3_sync_enabled = true
s3_encryption_enabled = true
s3_versioning_enabled = true
s3_lifecycle_enabled = true
load_balancer_enabled = true
fault_tolerance_enabled = true
EOF

# Initialize Terraform backend
terraform init \
    -backend-config="bucket=$TERRAFORM_BUCKET" \
    -backend-config="key=mapreduce/terraform.tfstate" \
    -backend-config="region=$AWS_REGION"

# Plan deployment
echo -e "${BLUE}📋 Planning deployment...${NC}"
terraform plan -out=tfplan

# Apply deployment
echo -e "${BLUE}🚀 Deploying infrastructure...${NC}"
terraform apply tfplan

# Get outputs
echo -e "${BLUE}📤 Getting deployment outputs...${NC}"
ALB_DNS=$(terraform output -raw alb_dns_name)
S3_BUCKET_NAME=$(terraform output -raw s3_bucket_name)

echo -e "${GREEN}✅ Infrastructure deployed successfully!${NC}"
echo "  Load Balancer DNS: $ALB_DNS"
echo "  S3 Bucket: $S3_BUCKET_NAME"

# Build and push Docker images
echo -e "${BLUE}🐳 Building Docker images...${NC}"
cd ../..

# Build the application
echo "Building MapReduce application..."
go build -o mapreduce src/*.go

# Create Docker image
echo "Creating Docker image..."
docker build -t $PROJECT_NAME:latest .

# Tag for AWS ECR (if using ECR)
# aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
# docker tag $PROJECT_NAME:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT_NAME:latest
# docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$PROJECT_NAME:latest

# Deploy application to EC2 instances
echo -e "${BLUE}🚀 Deploying application to EC2 instances...${NC}"

# Get EC2 instance IDs
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" "Name=instance-state-name,Values=running" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

echo "Found instances: $INSTANCE_IDS"

# Deploy to each instance
for instance_id in $INSTANCE_IDS; do
    echo "Deploying to instance: $instance_id"
    
    # Get instance public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $instance_id \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)
    
    echo "Instance public IP: $PUBLIC_IP"
    
    # Copy application files
    scp -i ~/.ssh/mapreduce-key.pem -o StrictHostKeyChecking=no \
        mapreduce ubuntu@$PUBLIC_IP:/home/ubuntu/
    
    # Copy configuration files
    scp -i ~/.ssh/mapreduce-key.pem -o StrictHostKeyChecking=no \
        aws/config/loadbalancer-s3.env ubuntu@$PUBLIC_IP:/home/ubuntu/
    
    # Execute deployment commands on instance
    ssh -i ~/.ssh/mapreduce-key.pem -o StrictHostKeyChecking=no ubuntu@$PUBLIC_IP << 'EOF'
        # Set environment variables
        export LOAD_BALANCER_ENABLED=true
        export S3_SYNC_ENABLED=true
        export AWS_S3_BUCKET=mapreduce-storage
        export AWS_REGION=us-east-1
        
        # Make application executable
        chmod +x /home/ubuntu/mapreduce
        
        # Start services
        echo "Starting MapReduce services..."
        
        # Start master (in background)
        nohup ./mapreduce master 0 /home/ubuntu/data/Words.txt > master.log 2>&1 &
        
        # Start worker (in background)
        nohup ./mapreduce worker > worker.log 2>&1 &
        
        # Start dashboard (in background)
        nohup ./mapreduce dashboard > dashboard.log 2>&1 &
        
        echo "Services started successfully"
EOF
done

# Test deployment
echo -e "${BLUE}🧪 Testing deployment...${NC}"

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Test health endpoint
echo "Testing health endpoint..."
if curl -f http://$ALB_DNS/health > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Health check passed${NC}"
else
    echo -e "${RED}❌ Health check failed${NC}"
fi

# Test load balancer
echo "Testing load balancer..."
if curl -f http://$ALB_DNS/api/v1/loadbalancer/stats > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Load balancer is working${NC}"
else
    echo -e "${YELLOW}⚠️  Load balancer endpoint not available${NC}"
fi

# Test S3 integration
echo "Testing S3 integration..."
if curl -f http://$ALB_DNS/api/v1/s3/stats > /dev/null 2>&1; then
    echo -e "${GREEN}✅ S3 integration is working${NC}"
else
    echo -e "${YELLOW}⚠️  S3 integration endpoint not available${NC}"
fi

# Display final information
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo ""
echo -e "${BLUE}📊 Access Information:${NC}"
echo "  Dashboard URL: http://$ALB_DNS"
echo "  Health Check: http://$ALB_DNS/health"
echo "  Load Balancer Stats: http://$ALB_DNS/api/v1/loadbalancer/stats"
echo "  S3 Stats: http://$ALB_DNS/api/v1/s3/stats"
echo ""
echo -e "${BLUE}🔧 Management Commands:${NC}"
echo "  View logs: ssh -i ~/.ssh/mapreduce-key.pem ubuntu@<instance-ip>"
echo "  Restart services: sudo systemctl restart mapreduce"
echo "  Check status: sudo systemctl status mapreduce"
echo ""
echo -e "${BLUE}📈 Monitoring:${NC}"
echo "  CloudWatch Logs: /aws/ec2/mapreduce"
echo "  S3 Bucket: $S3_BUCKET_NAME"
echo "  Load Balancer: $ALB_DNS"
echo ""
echo -e "${GREEN}✅ MapReduce with Load Balancer and S3 is now running!${NC}"
