# AWS Environment Setup Script for PowerShell
# This script sets up the AWS environment for MapReduce deployment

param(
    [string]$Region = "us-east-1",
    [string]$ProjectName = "mapreduce",
    [string]$Environment = "prod",
    [switch]$Help = $false
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$AwsDir = Join-Path $ProjectRoot "aws"
$ConfigDir = Join-Path $AwsDir "config"

# Functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    try {
        $null = Get-Command aws -ErrorAction Stop
    } catch {
        Write-Error "AWS CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if Terraform is installed
    try {
        $null = Get-Command terraform -ErrorAction Stop
    } catch {
        Write-Error "Terraform is not installed. Please install it first."
        exit 1
    }
    
    # Check if Docker is installed
    try {
        $null = Get-Command docker -ErrorAction Stop
    } catch {
        Write-Error "Docker is not installed. Please install it first."
        exit 1
    }
    
    Write-Success "All prerequisites are met"
}

function Initialize-AwsCredentials {
    Write-Info "Setting up AWS credentials..."
    
    # Check if AWS credentials are configured
    try {
        $null = aws sts get-caller-identity 2>$null
    } catch {
        Write-Warning "AWS credentials not configured. Please run 'aws configure' first."
        Write-Info "You can also set environment variables:"
        Write-Info "  `$env:AWS_ACCESS_KEY_ID = 'your-access-key'"
        Write-Info "  `$env:AWS_SECRET_ACCESS_KEY = 'your-secret-key'"
        Write-Info "  `$env:AWS_DEFAULT_REGION = 'us-east-1'"
        exit 1
    }
    
    # Get AWS account information
    $AwsAccountId = aws sts get-caller-identity --query Account --output text
    $AwsRegion = aws configure get region
    
    Write-Success "AWS credentials configured"
    Write-Info "Account ID: $AwsAccountId"
    Write-Info "Region: $AwsRegion"
    
    return @{
        AccountId = $AwsAccountId
        Region = $AwsRegion
    }
}

function New-ConfigFiles {
    Write-Info "Creating configuration files..."
    
    # Create .env file if it doesn't exist
    $EnvFile = Join-Path $ConfigDir ".env"
    if (-not (Test-Path $EnvFile)) {
        Write-Info "Creating .env file from template..."
        Copy-Item (Join-Path $ConfigDir "aws-config.env") $EnvFile
        Write-Warning "Please edit $EnvFile with your configuration"
    }
    
    # Create terraform.tfvars if it doesn't exist
    $TerraformFile = Join-Path $AwsDir "terraform\terraform.tfvars"
    if (-not (Test-Path $TerraformFile)) {
        Write-Info "Creating terraform.tfvars from template..."
        Copy-Item (Join-Path $AwsDir "terraform\terraform.tfvars.example") $TerraformFile
        Write-Warning "Please edit $TerraformFile with your configuration"
    }
    
    Write-Success "Configuration files created"
}

function Initialize-EnvironmentVariables {
    Write-Info "Setting up environment variables..."
    
    # Load .env file if it exists
    $EnvFile = Join-Path $ConfigDir ".env"
    if (Test-Path $EnvFile) {
        Get-Content $EnvFile | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                $Name = $Matches[1].Trim()
                $Value = $Matches[2].Trim()
                [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
            }
        }
        Write-Success "Environment variables loaded from .env"
    } else {
        Write-Warning ".env file not found, using default values"
    }
    
    # Set default values
    $env:AWS_REGION = if ($env:AWS_REGION) { $env:AWS_REGION } else { $Region }
    $env:PROJECT_NAME = if ($env:PROJECT_NAME) { $env:PROJECT_NAME } else { $ProjectName }
    $env:ENVIRONMENT = if ($env:ENVIRONMENT) { $env:ENVIRONMENT } else { $Environment }
    $env:INSTANCE_TYPE = if ($env:INSTANCE_TYPE) { $env:INSTANCE_TYPE } else { "t3.medium" }
    $env:MIN_INSTANCES = if ($env:MIN_INSTANCES) { $env:MIN_INSTANCES } else { "2" }
    $env:MAX_INSTANCES = if ($env:MAX_INSTANCES) { $env:MAX_INSTANCES } else { "10" }
    $env:DESIRED_INSTANCES = if ($env:DESIRED_INSTANCES) { $env:DESIRED_INSTANCES } else { "3" }
    
    Write-Success "Environment variables configured"
}

function New-TerraformStateBucket {
    param([string]$BucketName, [string]$Region)
    
    Write-Info "Creating S3 bucket for Terraform state..."
    
    # Check if bucket exists
    try {
        $null = aws s3 ls "s3://$BucketName" 2>$null
        Write-Info "Terraform state bucket already exists: $BucketName"
    } catch {
        # Create bucket
        aws s3 mb "s3://$BucketName" --region $Region
        
        # Enable versioning
        aws s3api put-bucket-versioning `
            --bucket $BucketName `
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption `
            --bucket $BucketName `
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }'
        
        Write-Success "Terraform state bucket created: $BucketName"
    }
}

function New-TerraformStateTable {
    param([string]$TableName)
    
    Write-Info "Creating DynamoDB table for Terraform state locking..."
    
    # Check if table exists
    try {
        $null = aws dynamodb describe-table --table-name $TableName 2>$null
        Write-Info "Terraform state lock table already exists: $TableName"
    } catch {
        # Create table
        aws dynamodb create-table `
            --table-name $TableName `
            --attribute-definitions AttributeName=LockID,AttributeType=S `
            --key-schema AttributeName=LockID,KeyType=HASH `
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name $TableName
        
        Write-Success "Terraform state lock table created: $TableName"
    }
}

function Initialize-TerraformBackend {
    param([string]$ProjectName, [string]$AccountId, [string]$Region)
    
    Write-Info "Setting up Terraform backend..."
    
    # Create backend configuration
    $BackendConfig = @"
terraform {
  backend "s3" {
    bucket         = "$ProjectName-terraform-state-$AccountId"
    key            = "mapreduce/terraform.tfstate"
    region         = "$Region"
    dynamodb_table = "$ProjectName-terraform-state-lock"
    encrypt        = true
  }
}
"@
    
    $BackendFile = Join-Path $AwsDir "terraform\backend.tf"
    $BackendConfig | Out-File -FilePath $BackendFile -Encoding UTF8
    
    Write-Success "Terraform backend configured"
}

function Test-KeyPair {
    param([string]$KeyPairName)
    
    Write-Info "Checking for EC2 key pair..."
    
    # Check if key pair exists
    try {
        $null = aws ec2 describe-key-pairs --key-names $KeyPairName 2>$null
        Write-Info "Key pair already exists: $KeyPairName"
    } catch {
        Write-Warning "Key pair not found: $KeyPairName"
        Write-Info "You can create a key pair using:"
        Write-Info "  aws ec2 create-key-pair --key-name $KeyPairName --query 'KeyMaterial' --output text > ~/.ssh/$KeyPairName.pem"
        Write-Info "  chmod 400 ~/.ssh/$KeyPairName.pem"
    }
}

function New-CloudWatchLogGroup {
    param([string]$LogGroupName)
    
    Write-Info "Creating CloudWatch log group..."
    
    # Check if log group exists
    try {
        $null = aws logs describe-log-groups --log-group-name-prefix $LogGroupName --query "logGroups[?logGroupName=='$LogGroupName']" --output text | Select-String $LogGroupName
        Write-Info "CloudWatch log group already exists: $LogGroupName"
    } catch {
        # Create log group
        aws logs create-log-group --log-group-name $LogGroupName
        
        # Set retention policy
        aws logs put-retention-policy `
            --log-group-name $LogGroupName `
            --retention-in-days 30
        
        Write-Success "CloudWatch log group created: $LogGroupName"
    }
}

function Initialize-Terraform {
    Write-Info "Initializing Terraform..."
    
    Set-Location (Join-Path $AwsDir "terraform")
    
    # Initialize Terraform
    terraform init
    
    Write-Success "Terraform initialized"
}

function Test-TerraformConfig {
    Write-Info "Validating Terraform configuration..."
    
    Set-Location (Join-Path $AwsDir "terraform")
    
    if (terraform validate) {
        Write-Success "Terraform configuration is valid"
    } else {
        Write-Error "Terraform configuration validation failed"
        exit 1
    }
}

function Show-NextSteps {
    param([string]$ProjectName, [string]$AccountId, [string]$Region)
    
    Write-Success "AWS environment setup completed!"
    Write-Host ""
    Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Edit configuration files:"
    Write-Host "   - $ConfigDir\.env"
    Write-Host "   - $AwsDir\terraform\terraform.tfvars"
    Write-Host ""
    Write-Host "2. Deploy infrastructure:"
    Write-Host "   .\scripts\deploy-aws.ps1"
    Write-Host ""
    Write-Host "3. Or use Makefile:"
    Write-Host "   make aws-deploy"
    Write-Host ""
    Write-Host "4. Monitor deployment:"
    Write-Host "   make aws-status"
    Write-Host "   make aws-logs"
    Write-Host ""
    Write-Host "=== CONFIGURATION FILES ===" -ForegroundColor Cyan
    Write-Host "Environment: $ConfigDir\.env"
    Write-Host "Terraform: $AwsDir\terraform\terraform.tfvars"
    Write-Host "Backend: $AwsDir\terraform\backend.tf"
    Write-Host ""
    Write-Host "=== AWS RESOURCES CREATED ===" -ForegroundColor Cyan
    Write-Host "S3 Bucket: $ProjectName-terraform-state-$AccountId"
    Write-Host "DynamoDB Table: $ProjectName-terraform-state-lock"
    Write-Host "CloudWatch Log Group: /aws/ec2/mapreduce"
    Write-Host ""
}

function Show-Help {
    Write-Host "AWS Environment Setup Script for MapReduce Project" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\setup-aws-env.ps1 [OPTIONS]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Region REGION        AWS region (default: us-east-1)"
    Write-Host "  -ProjectName NAME     Project name (default: mapreduce)"
    Write-Host "  -Environment ENV       Environment (default: prod)"
    Write-Host "  -Help                 Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\setup-aws-env.ps1                      # Setup with default settings"
    Write-Host "  .\setup-aws-env.ps1 -Region us-west-2   # Setup in us-west-2 region"
    Write-Host "  .\setup-aws-env.ps1 -ProjectName myapp  # Setup with custom project name"
}

# Main execution
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Info "Starting AWS environment setup..."
    Write-Info "Region: $Region"
    Write-Info "Project: $ProjectName"
    Write-Info "Environment: $Environment"
    
    # Check prerequisites
    Test-Prerequisites
    
    # Setup AWS credentials
    $AwsInfo = Initialize-AwsCredentials
    
    # Create configuration files
    New-ConfigFiles
    
    # Setup environment variables
    Initialize-EnvironmentVariables
    
    # Create Terraform state bucket
    $BucketName = "$ProjectName-terraform-state-$($AwsInfo.AccountId)"
    New-TerraformStateBucket -BucketName $BucketName -Region $AwsInfo.Region
    
    # Create Terraform state table
    $TableName = "$ProjectName-terraform-state-lock"
    New-TerraformStateTable -TableName $TableName
    
    # Setup Terraform backend
    Initialize-TerraformBackend -ProjectName $ProjectName -AccountId $AwsInfo.AccountId -Region $AwsInfo.Region
    
    # Create key pair
    $KeyPairName = "$ProjectName-key-pair"
    Test-KeyPair -KeyPairName $KeyPairName
    
    # Create CloudWatch log group
    $LogGroupName = "/aws/ec2/mapreduce"
    New-CloudWatchLogGroup -LogGroupName $LogGroupName
    
    # Initialize Terraform
    Initialize-Terraform
    
    # Validate Terraform configuration
    Test-TerraformConfig
    
    # Show next steps
    Show-NextSteps -ProjectName $ProjectName -AccountId $AwsInfo.AccountId -Region $AwsInfo.Region
}

# Run main function
Main