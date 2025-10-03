# AWS Deployment Script for MapReduce Project
# This script deploys the MapReduce system to AWS EC2 with S3 and Load Balancer

param(
    [string]$Region = "us-east-1",
    [string]$ProjectName = "mapreduce",
    [string]$Environment = "prod",
    [string]$InstanceType = "t3.medium",
    [int]$MinInstances = 2,
    [int]$MaxInstances = 10,
    [int]$DesiredInstances = 3,
    [switch]$SkipTerraform = $false,
    [switch]$SkipDocker = $false,
    [switch]$SkipMonitoring = $false,
    [switch]$SkipBackup = $false,
    [switch]$Help = $false
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$AwsDir = Join-Path $ProjectRoot "aws"
$TerraformDir = Join-Path $AwsDir "terraform"
$DockerDir = Join-Path $AwsDir "docker"

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

function Initialize-EnvironmentVariables {
    Write-Info "Setting up environment variables..."
    
    # Set environment variables
    $env:AWS_REGION = $Region
    $env:PROJECT_NAME = $ProjectName
    $env:ENVIRONMENT = $Environment
    $env:INSTANCE_TYPE = $InstanceType
    $env:MIN_INSTANCES = $MinInstances
    $env:MAX_INSTANCES = $MaxInstances
    $env:DESIRED_INSTANCES = $DesiredInstances
    
    Write-Success "Environment variables configured"
}

function Initialize-Terraform {
    if ($SkipTerraform) {
        Write-Info "Skipping Terraform initialization"
        return
    }
    
    Write-Info "Initializing Terraform..."
    
    Set-Location $TerraformDir
    
    # Initialize Terraform
    terraform init
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform initialization failed"
        exit 1
    }
    
    Write-Success "Terraform initialized"
}

function Test-TerraformConfig {
    if ($SkipTerraform) {
        Write-Info "Skipping Terraform validation"
        return
    }
    
    Write-Info "Validating Terraform configuration..."
    
    Set-Location $TerraformDir
    
    if (terraform validate) {
        Write-Success "Terraform configuration is valid"
    } else {
        Write-Error "Terraform configuration validation failed"
        exit 1
    }
}

function New-TerraformPlan {
    if ($SkipTerraform) {
        Write-Info "Skipping Terraform plan"
        return
    }
    
    Write-Info "Creating Terraform plan..."
    
    Set-Location $TerraformDir
    
    # Create plan
    terraform plan -out=tfplan
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform plan failed"
        exit 1
    }
    
    Write-Success "Terraform plan created"
}

function Invoke-TerraformApply {
    if ($SkipTerraform) {
        Write-Info "Skipping Terraform apply"
        return
    }
    
    Write-Info "Applying Terraform configuration..."
    
    Set-Location $TerraformDir
    
    # Apply configuration
    terraform apply -auto-approve tfplan
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Terraform apply failed"
        exit 1
    }
    
    Write-Success "Terraform configuration applied"
}

function Build-DockerImages {
    if ($SkipDocker) {
        Write-Info "Skipping Docker build"
        return
    }
    
    Write-Info "Building Docker images..."
    
    Set-Location $ProjectRoot
    
    # Build master image
    Write-Info "Building master image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-master:latest --build-arg BUILD_TARGET=master .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Master image build failed"
        exit 1
    }
    
    # Build worker image
    Write-Info "Building worker image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-worker:latest --build-arg BUILD_TARGET=worker .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Worker image build failed"
        exit 1
    }
    
    # Build backup image
    Write-Info "Building backup image..."
    docker build -f docker/Dockerfile.aws -t mapreduce-backup:latest --build-arg BUILD_TARGET=backup .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Backup image build failed"
        exit 1
    }
    
    Write-Success "Docker images built successfully"
}

function Test-DockerImages {
    if ($SkipDocker) {
        Write-Info "Skipping Docker tests"
        return
    }
    
    Write-Info "Testing Docker images..."
    
    # Test master image
    Write-Info "Testing master image..."
    docker run --rm mapreduce-master:latest --version
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Master image test failed"
        exit 1
    }
    
    # Test worker image
    Write-Info "Testing worker image..."
    docker run --rm mapreduce-worker:latest --version
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Worker image test failed"
        exit 1
    }
    
    Write-Success "Docker images tested successfully"
}

function Initialize-Monitoring {
    if ($SkipMonitoring) {
        Write-Info "Skipping monitoring setup"
        return
    }
    
    Write-Info "Setting up monitoring..."
    
    # Create CloudWatch log groups
    $LogGroups = @(
        "/aws/ec2/mapreduce/master",
        "/aws/ec2/mapreduce/worker",
        "/aws/ec2/mapreduce/dashboard",
        "/aws/ec2/mapreduce/nginx-access",
        "/aws/ec2/mapreduce/nginx-error",
        "/aws/ec2/mapreduce/docker"
    )
    
    foreach ($LogGroup in $LogGroups) {
        try {
            aws logs create-log-group --log-group-name $LogGroup --region $Region
            Write-Info "Created log group: $LogGroup"
        } catch {
            Write-Info "Log group already exists: $LogGroup"
        }
    }
    
    Write-Success "Monitoring setup completed"
}

function Initialize-Backup {
    if ($SkipBackup) {
        Write-Info "Skipping backup setup"
        return
    }
    
    Write-Info "Setting up backup..."
    
    # Create S3 buckets
    $StorageBucket = "$ProjectName-storage-$(Get-Random)"
    $BackupBucket = "$ProjectName-backup-$(Get-Random)"
    
    try {
        aws s3 mb "s3://$StorageBucket" --region $Region
        Write-Info "Created storage bucket: $StorageBucket"
    } catch {
        Write-Error "Failed to create storage bucket"
        exit 1
    }
    
    try {
        aws s3 mb "s3://$BackupBucket" --region $Region
        Write-Info "Created backup bucket: $BackupBucket"
    } catch {
        Write-Error "Failed to create backup bucket"
        exit 1
    }
    
    Write-Success "Backup setup completed"
}

function Test-Deployment {
    Write-Info "Testing deployment..."
    
    # Get load balancer DNS name
    $LbDnsName = terraform output -raw load_balancer_dns_name
    
    if (-not $LbDnsName) {
        Write-Error "Could not get load balancer DNS name"
        exit 1
    }
    
    # Test health endpoint
    $HealthUrl = "http://$LbDnsName/health"
    Write-Info "Testing health endpoint: $HealthUrl"
    
    try {
        $Response = Invoke-WebRequest -Uri $HealthUrl -TimeoutSec 30
        if ($Response.StatusCode -eq 200) {
            Write-Success "Health check passed"
        } else {
            Write-Error "Health check failed with status: $($Response.StatusCode)"
            exit 1
        }
    } catch {
        Write-Error "Health check failed: $($_.Exception.Message)"
        exit 1
    }
    
    # Test dashboard endpoint
    $DashboardUrl = "http://$LbDnsName/dashboard"
    Write-Info "Testing dashboard endpoint: $DashboardUrl"
    
    try {
        $Response = Invoke-WebRequest -Uri $DashboardUrl -TimeoutSec 30
        if ($Response.StatusCode -eq 200) {
            Write-Success "Dashboard check passed"
        } else {
            Write-Warning "Dashboard check failed with status: $($Response.StatusCode)"
        }
    } catch {
        Write-Warning "Dashboard check failed: $($_.Exception.Message)"
    }
    
    Write-Success "Deployment testing completed"
}

function Show-DeploymentInfo {
    Write-Info "Getting deployment information..."
    
    Set-Location $TerraformDir
    
    # Get outputs
    $LbDnsName = terraform output -raw load_balancer_dns_name
    $S3Bucket = terraform output -raw s3_bucket_name
    $BackupBucket = terraform output -raw backup_bucket_name
    
    Write-Success "Deployment completed successfully!"
    Write-Host ""
    Write-Host "=== DEPLOYMENT INFORMATION ===" -ForegroundColor Cyan
    Write-Host "Load Balancer DNS: $LbDnsName"
    Write-Host "S3 Storage Bucket: $S3Bucket"
    Write-Host "S3 Backup Bucket: $BackupBucket"
    Write-Host ""
    Write-Host "=== ACCESS URLS ===" -ForegroundColor Cyan
    Write-Host "Dashboard: http://$LbDnsName/dashboard"
    Write-Host "Health Check: http://$LbDnsName/health"
    Write-Host "API Master: http://$LbDnsName/api/master"
    Write-Host "API Worker: http://$LbDnsName/api/worker"
    Write-Host ""
    Write-Host "=== MONITORING ===" -ForegroundColor Cyan
    Write-Host "CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=$Region#logsV2:log-groups"
    Write-Host "CloudWatch Metrics: https://console.aws.amazon.com/cloudwatch/home?region=$Region#metricsV2:"
    Write-Host ""
    Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Access the dashboard to monitor the system"
    Write-Host "2. Check CloudWatch logs for any issues"
    Write-Host "3. Monitor S3 buckets for data storage"
    Write-Host "4. Set up additional monitoring as needed"
    Write-Host ""
}

function Show-Help {
    Write-Host "AWS Deployment Script for MapReduce Project" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\deploy-aws.ps1 [OPTIONS]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Region REGION              AWS region (default: us-east-1)"
    Write-Host "  -ProjectName NAME            Project name (default: mapreduce)"
    Write-Host "  -Environment ENV             Environment (default: prod)"
    Write-Host "  -InstanceType TYPE           EC2 instance type (default: t3.medium)"
    Write-Host "  -MinInstances COUNT          Minimum instances (default: 2)"
    Write-Host "  -MaxInstances COUNT          Maximum instances (default: 10)"
    Write-Host "  -DesiredInstances COUNT      Desired instances (default: 3)"
    Write-Host "  -SkipTerraform               Skip Terraform deployment"
    Write-Host "  -SkipDocker                  Skip Docker build"
    Write-Host "  -SkipMonitoring              Skip monitoring setup"
    Write-Host "  -SkipBackup                  Skip backup setup"
    Write-Host "  -Help                        Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\deploy-aws.ps1                                    # Deploy with default settings"
    Write-Host "  .\deploy-aws.ps1 -Region us-west-2                # Deploy in us-west-2 region"
    Write-Host "  .\deploy-aws.ps1 -InstanceType t3.large            # Deploy with t3.large instances"
    Write-Host "  .\deploy-aws.ps1 -SkipTerraform                   # Skip Terraform deployment"
    Write-Host ""
}

# Main execution
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Info "Starting AWS deployment..."
    Write-Info "Region: $Region"
    Write-Info "Project: $ProjectName"
    Write-Info "Environment: $Environment"
    Write-Info "Instance Type: $InstanceType"
    Write-Info "Instances: $MinInstances-$MaxInstances (desired: $DesiredInstances)"
    
    # Check prerequisites
    Test-Prerequisites
    
    # Setup AWS credentials
    $AwsInfo = Initialize-AwsCredentials
    
    # Setup environment variables
    Initialize-EnvironmentVariables
    
    # Initialize Terraform
    Initialize-Terraform
    
    # Validate Terraform configuration
    Test-TerraformConfig
    
    # Create Terraform plan
    New-TerraformPlan
    
    # Apply Terraform configuration
    Invoke-TerraformApply
    
    # Build Docker images
    Build-DockerImages
    
    # Test Docker images
    Test-DockerImages
    
    # Setup monitoring
    Initialize-Monitoring
    
    # Setup backup
    Initialize-Backup
    
    # Test deployment
    Test-Deployment
    
    # Show deployment information
    Show-DeploymentInfo
}

# Run main function
Main
