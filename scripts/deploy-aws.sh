#!/bin/bash

# AWS Deployment Script for MapReduce Project
# This script deploys the MapReduce application to AWS EC2 with S3 and Load Balancer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/aws/terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-prod}"

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
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "All prerequisites are met"
}

setup_terraform() {
    log_info "Setting up Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    terraform init
    
    # Create terraform.tfvars if it doesn't exist
    if [ ! -f "terraform.tfvars" ]; then
        log_warning "terraform.tfvars not found. Creating from example..."
        cp terraform.tfvars.example terraform.tfvars
        log_warning "Please edit terraform.tfvars with your configuration before proceeding."
        exit 1
    fi
    
    log_success "Terraform setup completed"
}

validate_terraform() {
    log_info "Validating Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    if terraform validate; then
        log_success "Terraform configuration is valid"
    else
        log_error "Terraform configuration validation failed"
        exit 1
    fi
}

plan_terraform() {
    log_info "Planning Terraform deployment..."
    
    cd "$TERRAFORM_DIR"
    
    terraform plan -out=tfplan
    
    log_success "Terraform plan completed"
}

apply_terraform() {
    log_info "Applying Terraform configuration..."
    
    cd "$TERRAFORM_DIR"
    
    if terraform apply -auto-approve tfplan; then
        log_success "Terraform apply completed successfully"
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

get_outputs() {
    log_info "Getting Terraform outputs..."
    
    cd "$TERRAFORM_DIR"
    
    # Get outputs
    LOAD_BALANCER_DNS=$(terraform output -raw load_balancer_dns_name)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    VPC_ID=$(terraform output -raw vpc_id)
    
    log_success "Infrastructure deployed successfully!"
    echo ""
    echo "=== DEPLOYMENT INFORMATION ==="
    echo "Load Balancer DNS: $LOAD_BALANCER_DNS"
    echo "S3 Bucket: $S3_BUCKET"
    echo "VPC ID: $VPC_ID"
    echo ""
    echo "=== APPLICATION URLS ==="
    echo "Application URL: http://$LOAD_BALANCER_DNS"
    echo "Health Check URL: http://$LOAD_BALANCER_DNS/health"
    echo "Dashboard URL: http://$LOAD_BALANCER_DNS/dashboard"
    echo ""
    echo "=== MONITORING ==="
    echo "CloudWatch Logs: /aws/ec2/mapreduce"
    echo "S3 Data Bucket: $S3_BUCKET"
    echo ""
}

wait_for_health() {
    log_info "Waiting for application to be healthy..."
    
    cd "$TERRAFORM_DIR"
    LOAD_BALANCER_DNS=$(terraform output -raw load_balancer_dns_name)
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Health check attempt $attempt/$max_attempts..."
        
        if curl -f -s "http://$LOAD_BALANCER_DNS/health" > /dev/null; then
            log_success "Application is healthy!"
            return 0
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log_error "Application failed to become healthy within expected time"
    return 1
}

run_tests() {
    log_info "Running deployment tests..."
    
    cd "$TERRAFORM_DIR"
    LOAD_BALANCER_DNS=$(terraform output -raw load_balancer_dns_name)
    
    # Test health endpoint
    if curl -f -s "http://$LOAD_BALANCER_DNS/health" > /dev/null; then
        log_success "Health endpoint test passed"
    else
        log_error "Health endpoint test failed"
        return 1
    fi
    
    # Test dashboard endpoint
    if curl -f -s "http://$LOAD_BALANCER_DNS/dashboard" > /dev/null; then
        log_success "Dashboard endpoint test passed"
    else
        log_error "Dashboard endpoint test failed"
        return 1
    fi
    
    log_success "All tests passed!"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    
    cd "$TERRAFORM_DIR"
    rm -f tfplan
    
    log_success "Cleanup completed"
}

show_help() {
    echo "AWS Deployment Script for MapReduce Project"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -p, --plan-only         Only run terraform plan (don't apply)"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -r, --region REGION     AWS region (default: us-east-1)"
    echo "  -e, --env ENVIRONMENT   Environment (default: prod)"
    echo "  -t, --test              Run tests after deployment"
    echo "  -c, --cleanup           Clean up resources"
    echo ""
    echo "Examples:"
    echo "  $0                      # Deploy with default settings"
    echo "  $0 --plan-only          # Only plan the deployment"
    echo "  $0 --region us-west-2   # Deploy to us-west-2 region"
    echo "  $0 --test               # Deploy and run tests"
    echo "  $0 --cleanup            # Clean up all resources"
}

# Parse command line arguments
PLAN_ONLY=false
FORCE=false
RUN_TESTS=false
CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -p|--plan-only)
            PLAN_ONLY=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -t|--test)
            RUN_TESTS=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting AWS deployment for MapReduce project..."
    log_info "Region: $AWS_REGION"
    log_info "Environment: $ENVIRONMENT"
    
    if [ "$CLEANUP" = true ]; then
        log_info "Cleaning up AWS resources..."
        cd "$TERRAFORM_DIR"
        terraform destroy -auto-approve
        log_success "Cleanup completed"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup Terraform
    setup_terraform
    
    # Validate configuration
    validate_terraform
    
    # Plan deployment
    plan_terraform
    
    if [ "$PLAN_ONLY" = true ]; then
        log_success "Plan completed. Use --force to apply changes."
        exit 0
    fi
    
    # Confirm deployment
    if [ "$FORCE" = false ]; then
        echo ""
        log_warning "This will create AWS resources that may incur costs."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Apply Terraform
    apply_terraform
    
    # Get outputs
    get_outputs
    
    # Wait for health
    if wait_for_health; then
        log_success "Application is healthy and ready!"
    else
        log_error "Application failed to become healthy"
        exit 1
    fi
    
    # Run tests if requested
    if [ "$RUN_TESTS" = true ]; then
        run_tests
    fi
    
    # Cleanup
    cleanup
    
    log_success "AWS deployment completed successfully!"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Monitor your application in the AWS Console"
    echo "2. Check CloudWatch logs for any issues"
    echo "3. Configure monitoring and alerting as needed"
    echo "4. Set up backup strategies for your S3 data"
    echo ""
}

# Run main function
main "$@"