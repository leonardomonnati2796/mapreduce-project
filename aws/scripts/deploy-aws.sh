#!/bin/bash

# AWS Deployment Script for MapReduce Project
# This script deploys the MapReduce system to AWS EC2 with S3 and Load Balancer

set -e

# Default values
REGION="us-east-1"
PROJECT_NAME="mapreduce"
ENVIRONMENT="prod"
INSTANCE_TYPE="t3.medium"
MIN_INSTANCES=2
MAX_INSTANCES=10
DESIRED_INSTANCES=3
SKIP_TERRAFORM=false
SKIP_DOCKER=false
SKIP_MONITORING=false
SKIP_BACKUP=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    echo -e "${CYAN}AWS Deployment Script for MapReduce Project${NC}"
    echo ""
    echo -e "${YELLOW}Usage: ./deploy-aws.sh [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -r, --region REGION              AWS region (default: us-east-1)"
    echo "  -p, --project-name NAME          Project name (default: mapreduce)"
    echo "  -e, --environment ENV             Environment (default: prod)"
    echo "  -i, --instance-type TYPE         EC2 instance type (default: t3.medium)"
    echo "  --min-instances COUNT            Minimum instances (default: 2)"
    echo "  --max-instances COUNT            Maximum instances (default: 10)"
    echo "  --desired-instances COUNT        Desired instances (default: 3)"
    echo "  --skip-terraform                 Skip Terraform deployment"
    echo "  --skip-docker                    Skip Docker build"
    echo "  --skip-monitoring                Skip monitoring setup"
    echo "  --skip-backup                    Skip backup setup"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./deploy-aws.sh                                    # Deploy with default settings"
    echo "  ./deploy-aws.sh -r us-west-2                      # Deploy in us-west-2 region"
    echo "  ./deploy-aws.sh -i t3.large                      # Deploy with t3.large instances"
    echo "  ./deploy-aws.sh --skip-terraform                 # Skip Terraform deployment"
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

setup_aws_credentials() {
    log_info "Setting up AWS credentials..."
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_warning "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    log_success "AWS credentials configured"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "Region: $AWS_REGION"
}

setup_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$REGION
    export PROJECT_NAME=$PROJECT_NAME
    export ENVIRONMENT=$ENVIRONMENT
    export INSTANCE_TYPE=$INSTANCE_TYPE
    export MIN_INSTANCES=$MIN_INSTANCES
    export MAX_INSTANCES=$MAX_INSTANCES
    export DESIRED_INSTANCES=$DESIRED_INSTANCES
    
    log_success "Environment variables configured"
}

initialize_terraform() {
    if [ "$SKIP_TERRAFORM" = true ]; then
        log_info "Skipping Terraform initialization"
        return
    fi
    
    log_info "Initializing Terraform..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    # Initialize Terraform
    terraform init
    
    if [ $? -ne 0 ]; then
        log_error "Terraform initialization failed"
        exit 1
    fi
    
    log_success "Terraform initialized"
}

validate_terraform_config() {
    if [ "$SKIP_TERRAFORM" = true ]; then
        log_info "Skipping Terraform validation"
        return
    fi
    
    log_info "Validating Terraform configuration..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    if terraform validate; then
        log_success "Terraform configuration is valid"
    else
        log_error "Terraform configuration validation failed"
        exit 1
    fi
}

create_terraform_plan() {
    if [ "$SKIP_TERRAFORM" = true ]; then
        log_info "Skipping Terraform plan"
        return
    fi
    
    log_info "Creating Terraform plan..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    # Create plan
    terraform plan -out=tfplan
    
    if [ $? -ne 0 ]; then
        log_error "Terraform plan failed"
        exit 1
    fi
    
    log_success "Terraform plan created"
}

apply_terraform_config() {
    if [ "$SKIP_TERRAFORM" = true ]; then
        log_info "Skipping Terraform apply"
        return
    fi
    
    log_info "Applying Terraform configuration..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    # Apply configuration
    terraform apply -auto-approve tfplan
    
    if [ $? -ne 0 ]; then
        log_error "Terraform apply failed"
        exit 1
    fi
    
    log_success "Terraform configuration applied"
}

build_docker_images() {
    if [ "$SKIP_DOCKER" = true ]; then
        log_info "Skipping Docker build"
        return
    fi
    
    log_info "Building Docker images..."
    
    cd "$PROJECT_ROOT"
    
    # Build master image
    log_info "Building master image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-master:latest --build-arg BUILD_TARGET=master .
    
    if [ $? -ne 0 ]; then
        log_error "Master image build failed"
        exit 1
    fi
    
    # Build worker image
    log_info "Building worker image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-worker:latest --build-arg BUILD_TARGET=worker .
    
    if [ $? -ne 0 ]; then
        log_error "Worker image build failed"
        exit 1
    fi
    
    # Build backup image
    log_info "Building backup image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-backup:latest --build-arg BUILD_TARGET=backup .
    
    if [ $? -ne 0 ]; then
        log_error "Backup image build failed"
        exit 1
    fi
    
    log_success "Docker images built successfully"
}

test_docker_images() {
    if [ "$SKIP_DOCKER" = true ]; then
        log_info "Skipping Docker tests"
        return
    fi
    
    log_info "Testing Docker images..."
    
    # Test master image
    log_info "Testing master image..."
    docker run --rm mapreduce-master:latest --version
    
    if [ $? -ne 0 ]; then
        log_error "Master image test failed"
        exit 1
    fi
    
    # Test worker image
    log_info "Testing worker image..."
    docker run --rm mapreduce-worker:latest --version
    
    if [ $? -ne 0 ]; then
        log_error "Worker image test failed"
        exit 1
    fi
    
    log_success "Docker images tested successfully"
}

setup_monitoring() {
    if [ "$SKIP_MONITORING" = true ]; then
        log_info "Skipping monitoring setup"
        return
    fi
    
    log_info "Setting up monitoring..."
    
    # Create CloudWatch log groups
    LOG_GROUPS=(
        "/aws/ec2/mapreduce/master"
        "/aws/ec2/mapreduce/worker"
        "/aws/ec2/mapreduce/dashboard"
        "/aws/ec2/mapreduce/nginx-access"
        "/aws/ec2/mapreduce/nginx-error"
        "/aws/ec2/mapreduce/docker"
    )
    
    for LOG_GROUP in "${LOG_GROUPS[@]}"; do
        if aws logs describe-log-groups --log-group-name "$LOG_GROUP" --region "$REGION" &> /dev/null; then
            log_info "Log group already exists: $LOG_GROUP"
        else
            aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$REGION"
            log_info "Created log group: $LOG_GROUP"
        fi
    done
    
    log_success "Monitoring setup completed"
}

setup_backup() {
    if [ "$SKIP_BACKUP" = true ]; then
        log_info "Skipping backup setup"
        return
    fi
    
    log_info "Setting up backup..."
    
    # Create S3 buckets
    STORAGE_BUCKET="${PROJECT_NAME}-storage-$(date +%s)"
    BACKUP_BUCKET="${PROJECT_NAME}-backup-$(date +%s)"
    
    if aws s3 mb "s3://$STORAGE_BUCKET" --region "$REGION"; then
        log_info "Created storage bucket: $STORAGE_BUCKET"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    if aws s3 mb "s3://$BACKUP_BUCKET" --region "$REGION"; then
        log_info "Created backup bucket: $BACKUP_BUCKET"
    else
        log_error "Failed to create backup bucket"
        exit 1
    fi
    
    log_success "Backup setup completed"
}

test_deployment() {
    log_info "Testing deployment..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    # Get load balancer DNS name
    LB_DNS_NAME=$(terraform output -raw load_balancer_dns_name)
    
    if [ -z "$LB_DNS_NAME" ]; then
        log_error "Could not get load balancer DNS name"
        exit 1
    fi
    
    # Test health endpoint
    HEALTH_URL="http://$LB_DNS_NAME/health"
    log_info "Testing health endpoint: $HEALTH_URL"
    
    if curl -f -s --max-time 30 "$HEALTH_URL" > /dev/null; then
        log_success "Health check passed"
    else
        log_error "Health check failed"
        exit 1
    fi
    
    # Test dashboard endpoint
    DASHBOARD_URL="http://$LB_DNS_NAME/dashboard"
    log_info "Testing dashboard endpoint: $DASHBOARD_URL"
    
    if curl -f -s --max-time 30 "$DASHBOARD_URL" > /dev/null; then
        log_success "Dashboard check passed"
    else
        log_warning "Dashboard check failed"
    fi
    
    log_success "Deployment testing completed"
}

show_deployment_info() {
    log_info "Getting deployment information..."
    
    cd "$SCRIPT_DIR/../terraform"
    
    # Get outputs
    LB_DNS_NAME=$(terraform output -raw load_balancer_dns_name)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    BACKUP_BUCKET=$(terraform output -raw backup_bucket_name)
    
    log_success "Deployment completed successfully!"
    echo ""
    echo -e "${CYAN}=== DEPLOYMENT INFORMATION ===${NC}"
    echo "Load Balancer DNS: $LB_DNS_NAME"
    echo "S3 Storage Bucket: $S3_BUCKET"
    echo "S3 Backup Bucket: $BACKUP_BUCKET"
    echo ""
    echo -e "${CYAN}=== ACCESS URLS ===${NC}"
    echo "Dashboard: http://$LB_DNS_NAME/dashboard"
    echo "Health Check: http://$LB_DNS_NAME/health"
    echo "API Master: http://$LB_DNS_NAME/api/master"
    echo "API Worker: http://$LB_DNS_NAME/api/worker"
    echo ""
    echo -e "${CYAN}=== MONITORING ===${NC}"
    echo "CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups"
    echo "CloudWatch Metrics: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#metricsV2:"
    echo ""
    echo -e "${CYAN}=== NEXT STEPS ===${NC}"
    echo "1. Access the dashboard to monitor the system"
    echo "2. Check CloudWatch logs for any issues"
    echo "3. Monitor S3 buckets for data storage"
    echo "4. Set up additional monitoring as needed"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -i|--instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --min-instances)
            MIN_INSTANCES="$2"
            shift 2
            ;;
        --max-instances)
            MAX_INSTANCES="$2"
            shift 2
            ;;
        --desired-instances)
            DESIRED_INSTANCES="$2"
            shift 2
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Main execution
log_info "Starting AWS deployment..."
log_info "Region: $REGION"
log_info "Project: $PROJECT_NAME"
log_info "Environment: $ENVIRONMENT"
log_info "Instance Type: $INSTANCE_TYPE"
log_info "Instances: $MIN_INSTANCES-$MAX_INSTANCES (desired: $DESIRED_INSTANCES)"

# Check prerequisites
check_prerequisites

# Setup AWS credentials
setup_aws_credentials

# Setup environment variables
setup_environment_variables

# Initialize Terraform
initialize_terraform

# Validate Terraform configuration
validate_terraform_config

# Create Terraform plan
create_terraform_plan

# Apply Terraform configuration
apply_terraform_config

# Build Docker images
build_docker_images

# Test Docker images
test_docker_images

# Setup monitoring
setup_monitoring

# Setup backup
setup_backup

# Test deployment
test_deployment

# Show deployment information
show_deployment_info
