#!/bin/bash

# AWS Environment Setup Script for MapReduce Project
# This script sets up the AWS environment for MapReduce deployment

set -e

# Default values
REGION="us-east-1"
PROJECT_NAME="mapreduce"
ENVIRONMENT="prod"

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
    echo -e "${CYAN}AWS Environment Setup Script for MapReduce Project${NC}"
    echo ""
    echo -e "${YELLOW}Usage: ./setup-aws-env.sh [OPTIONS]${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  -r, --region REGION              AWS region (default: us-east-1)"
    echo "  -p, --project-name NAME          Project name (default: mapreduce)"
    echo "  -e, --environment ENV             Environment (default: prod)"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./setup-aws-env.sh                      # Setup with default settings"
    echo "  ./setup-aws-env.sh -r us-west-2         # Setup in us-west-2 region"
    echo "  ./setup-aws-env.sh -p myapp             # Setup with custom project name"
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
        log_info "You can also set environment variables:"
        log_info "  export AWS_ACCESS_KEY_ID='your-access-key'"
        log_info "  export AWS_SECRET_ACCESS_KEY='your-secret-key'"
        log_info "  export AWS_DEFAULT_REGION='us-east-1'"
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    log_success "AWS credentials configured"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "Region: $AWS_REGION"
}

create_config_files() {
    log_info "Creating configuration files..."
    
    # Create .env file if it doesn't exist
    ENV_FILE="$CONFIG_DIR/.env"
    if [ ! -f "$ENV_FILE" ]; then
        log_info "Creating .env file from template..."
        cp "$CONFIG_DIR/aws-config.env" "$ENV_FILE"
        log_warning "Please edit $ENV_FILE with your configuration"
    fi
    
    # Create terraform.tfvars if it doesn't exist
    TERRAFORM_FILE="$AWS_DIR/terraform/terraform.tfvars"
    if [ ! -f "$TERRAFORM_FILE" ]; then
        log_info "Creating terraform.tfvars from template..."
        cp "$AWS_DIR/terraform/terraform.tfvars.example" "$TERRAFORM_FILE"
        log_warning "Please edit $TERRAFORM_FILE with your configuration"
    fi
    
    log_success "Configuration files created"
}

setup_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Load .env file if it exists
    ENV_FILE="$CONFIG_DIR/.env"
    if [ -f "$ENV_FILE" ]; then
        set -a
        source "$ENV_FILE"
        set +a
        log_success "Environment variables loaded from .env"
    else
        log_warning ".env file not found, using default values"
    fi
    
    # Set default values
    export AWS_REGION=${AWS_REGION:-$REGION}
    export PROJECT_NAME=${PROJECT_NAME:-$PROJECT_NAME}
    export ENVIRONMENT=${ENVIRONMENT:-$ENVIRONMENT}
    export INSTANCE_TYPE=${INSTANCE_TYPE:-"t3.medium"}
    export MIN_INSTANCES=${MIN_INSTANCES:-"2"}
    export MAX_INSTANCES=${MAX_INSTANCES:-"10"}
    export DESIRED_INSTANCES=${DESIRED_INSTANCES:-"3"}
    
    log_success "Environment variables configured"
}

create_terraform_state_bucket() {
    local bucket_name=$1
    local region=$2
    
    log_info "Creating S3 bucket for Terraform state..."
    
    # Check if bucket exists
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        log_info "Terraform state bucket already exists: $bucket_name"
    else
        # Create bucket
        aws s3 mb "s3://$bucket_name" --region "$region"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket_name" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        log_success "Terraform state bucket created: $bucket_name"
    fi
}

create_terraform_state_table() {
    local table_name=$1
    
    log_info "Creating DynamoDB table for Terraform state locking..."
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$table_name" &> /dev/null; then
        log_info "Terraform state lock table already exists: $table_name"
    else
        # Create table
        aws dynamodb create-table \
            --table-name "$table_name" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$table_name"
        
        log_success "Terraform state lock table created: $table_name"
    fi
}

setup_terraform_backend() {
    local project_name=$1
    local account_id=$2
    local region=$3
    
    log_info "Setting up Terraform backend..."
    
    # Create backend configuration
    cat > "$AWS_DIR/terraform/backend.tf" << EOF
terraform {
  backend "s3" {
    bucket         = "$project_name-terraform-state-$account_id"
    key            = "mapreduce/terraform.tfstate"
    region         = "$region"
    dynamodb_table = "$project_name-terraform-state-lock"
    encrypt        = true
  }
}
EOF
    
    log_success "Terraform backend configured"
}

check_key_pair() {
    local key_pair_name=$1
    
    log_info "Checking for EC2 key pair..."
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs --key-names "$key_pair_name" &> /dev/null; then
        log_info "Key pair already exists: $key_pair_name"
    else
        log_warning "Key pair not found: $key_pair_name"
        log_info "You can create a key pair using:"
        log_info "  aws ec2 create-key-pair --key-name $key_pair_name --query 'KeyMaterial' --output text > ~/.ssh/$key_pair_name.pem"
        log_info "  chmod 400 ~/.ssh/$key_pair_name.pem"
    fi
}

create_cloudwatch_log_group() {
    local log_group_name=$1
    
    log_info "Creating CloudWatch log group..."
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query "logGroups[?logGroupName=='$log_group_name']" --output text | grep -q "$log_group_name"; then
        log_info "CloudWatch log group already exists: $log_group_name"
    else
        # Create log group
        aws logs create-log-group --log-group-name "$log_group_name"
        
        # Set retention policy
        aws logs put-retention-policy \
            --log-group-name "$log_group_name" \
            --retention-in-days 30
        
        log_success "CloudWatch log group created: $log_group_name"
    fi
}

initialize_terraform() {
    log_info "Initializing Terraform..."
    
    cd "$AWS_DIR/terraform"
    
    # Initialize Terraform
    terraform init
    
    log_success "Terraform initialized"
}

validate_terraform_config() {
    log_info "Validating Terraform configuration..."
    
    cd "$AWS_DIR/terraform"
    
    if terraform validate; then
        log_success "Terraform configuration is valid"
    else
        log_error "Terraform configuration validation failed"
        exit 1
    fi
}

show_next_steps() {
    local project_name=$1
    local account_id=$2
    local region=$3
    
    log_success "AWS environment setup completed!"
    echo ""
    echo -e "${CYAN}=== NEXT STEPS ===${NC}"
    echo "1. Edit configuration files:"
    echo "   - $CONFIG_DIR/.env"
    echo "   - $AWS_DIR/terraform/terraform.tfvars"
    echo ""
    echo "2. Deploy infrastructure:"
    echo "   ./scripts/deploy-aws.sh"
    echo ""
    echo "3. Or use Makefile:"
    echo "   make aws-deploy"
    echo ""
    echo "4. Monitor deployment:"
    echo "   make aws-status"
    echo "   make aws-logs"
    echo ""
    echo -e "${CYAN}=== CONFIGURATION FILES ===${NC}"
    echo "Environment: $CONFIG_DIR/.env"
    echo "Terraform: $AWS_DIR/terraform/terraform.tfvars"
    echo "Backend: $AWS_DIR/terraform/backend.tf"
    echo ""
    echo -e "${CYAN}=== AWS RESOURCES CREATED ===${NC}"
    echo "S3 Bucket: $project_name-terraform-state-$account_id"
    echo "DynamoDB Table: $project_name-terraform-state-lock"
    echo "CloudWatch Log Group: /aws/ec2/mapreduce"
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
AWS_DIR="$PROJECT_ROOT/aws"
CONFIG_DIR="$AWS_DIR/config"

# Main execution
log_info "Starting AWS environment setup..."
log_info "Region: $REGION"
log_info "Project: $PROJECT_NAME"
log_info "Environment: $ENVIRONMENT"

# Check prerequisites
check_prerequisites

# Setup AWS credentials
setup_aws_credentials

# Create configuration files
create_config_files

# Setup environment variables
setup_environment_variables

# Create Terraform state bucket
BUCKET_NAME="$PROJECT_NAME-terraform-state-$AWS_ACCOUNT_ID"
create_terraform_state_bucket "$BUCKET_NAME" "$AWS_REGION"

# Create Terraform state table
TABLE_NAME="$PROJECT_NAME-terraform-state-lock"
create_terraform_state_table "$TABLE_NAME"

# Setup Terraform backend
setup_terraform_backend "$PROJECT_NAME" "$AWS_ACCOUNT_ID" "$AWS_REGION"

# Create key pair
KEY_PAIR_NAME="$PROJECT_NAME-key-pair"
check_key_pair "$KEY_PAIR_NAME"

# Create CloudWatch log group
LOG_GROUP_NAME="/aws/ec2/mapreduce"
create_cloudwatch_log_group "$LOG_GROUP_NAME"

# Initialize Terraform
initialize_terraform

# Validate Terraform configuration
validate_terraform_config

# Show next steps
show_next_steps "$PROJECT_NAME" "$AWS_ACCOUNT_ID" "$AWS_REGION"