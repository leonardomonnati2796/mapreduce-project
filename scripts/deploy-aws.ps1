# AWS Deployment Script for MapReduce Project
# PowerShell script for deploying to AWS EC2 with S3 and Load Balancer

param(
    [string]$Region = "us-east-1",
    [string]$Environment = "prod",
    [switch]$PlanOnly = $false,
    [switch]$Force = $false,
    [switch]$Test = $false,
    [switch]$Cleanup = $false,
    [switch]$Help = $false
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$TerraformDir = Join-Path $ProjectRoot "aws\terraform"

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
    
    # Check AWS credentials
    try {
        $null = aws sts get-caller-identity 2>$null
    } catch {
        Write-Error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    }
    
    Write-Success "All prerequisites are met"
}

function Initialize-Terraform {
    Write-Info "Setting up Terraform..."
    
    Set-Location $TerraformDir
    
    # Initialize Terraform
    terraform init
    
    # Create terraform.tfvars if it doesn't exist
    if (-not (Test-Path "terraform.tfvars")) {
        Write-Warning "terraform.tfvars not found. Creating from example..."
        Copy-Item "terraform.tfvars.example" "terraform.tfvars"
        Write-Warning "Please edit terraform.tfvars with your configuration before proceeding."
        exit 1
    }
    
    Write-Success "Terraform setup completed"
}

function Test-TerraformConfig {
    Write-Info "Validating Terraform configuration..."
    
    Set-Location $TerraformDir
    
    if (terraform validate) {
        Write-Success "Terraform configuration is valid"
    } else {
        Write-Error "Terraform configuration validation failed"
        exit 1
    }
}

function Invoke-TerraformPlan {
    Write-Info "Planning Terraform deployment..."
    
    Set-Location $TerraformDir
    
    terraform plan -out=tfplan
    
    Write-Success "Terraform plan completed"
}

function Invoke-TerraformApply {
    Write-Info "Applying Terraform configuration..."
    
    Set-Location $TerraformDir
    
    if (terraform apply -auto-approve tfplan) {
        Write-Success "Terraform apply completed successfully"
    } else {
        Write-Error "Terraform apply failed"
        exit 1
    }
}

function Get-TerraformOutputs {
    Write-Info "Getting Terraform outputs..."
    
    Set-Location $TerraformDir
    
    # Get outputs
    $LoadBalancerDNS = terraform output -raw load_balancer_dns_name
    $S3Bucket = terraform output -raw s3_bucket_name
    $VPCId = terraform output -raw vpc_id
    
    Write-Success "Infrastructure deployed successfully!"
    Write-Host ""
    Write-Host "=== DEPLOYMENT INFORMATION ===" -ForegroundColor Cyan
    Write-Host "Load Balancer DNS: $LoadBalancerDNS"
    Write-Host "S3 Bucket: $S3Bucket"
    Write-Host "VPC ID: $VPCId"
    Write-Host ""
    Write-Host "=== APPLICATION URLS ===" -ForegroundColor Cyan
    Write-Host "Application URL: http://$LoadBalancerDNS"
    Write-Host "Health Check URL: http://$LoadBalancerDNS/health"
    Write-Host "Dashboard URL: http://$LoadBalancerDNS/dashboard"
    Write-Host ""
    Write-Host "=== MONITORING ===" -ForegroundColor Cyan
    Write-Host "CloudWatch Logs: /aws/ec2/mapreduce"
    Write-Host "S3 Data Bucket: $S3Bucket"
    Write-Host ""
}

function Wait-ForHealth {
    Write-Info "Waiting for application to be healthy..."
    
    Set-Location $TerraformDir
    $LoadBalancerDNS = terraform output -raw load_balancer_dns_name
    
    $MaxAttempts = 30
    $Attempt = 1
    
    while ($Attempt -le $MaxAttempts) {
        Write-Info "Health check attempt $Attempt/$MaxAttempts..."
        
        try {
            $Response = Invoke-WebRequest -Uri "http://$LoadBalancerDNS/health" -TimeoutSec 10 -ErrorAction Stop
            if ($Response.StatusCode -eq 200) {
                Write-Success "Application is healthy!"
                return $true
            }
        } catch {
            # Continue to next attempt
        }
        
        Start-Sleep -Seconds 10
        $Attempt++
    }
    
    Write-Error "Application failed to become healthy within expected time"
    return $false
}

function Invoke-DeploymentTests {
    Write-Info "Running deployment tests..."
    
    Set-Location $TerraformDir
    $LoadBalancerDNS = terraform output -raw load_balancer_dns_name
    
    # Test health endpoint
    try {
        $Response = Invoke-WebRequest -Uri "http://$LoadBalancerDNS/health" -TimeoutSec 10 -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            Write-Success "Health endpoint test passed"
        } else {
            Write-Error "Health endpoint test failed"
            return $false
        }
    } catch {
        Write-Error "Health endpoint test failed: $($_.Exception.Message)"
        return $false
    }
    
    # Test dashboard endpoint
    try {
        $Response = Invoke-WebRequest -Uri "http://$LoadBalancerDNS/dashboard" -TimeoutSec 10 -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            Write-Success "Dashboard endpoint test passed"
        } else {
            Write-Error "Dashboard endpoint test failed"
            return $false
        }
    } catch {
        Write-Error "Dashboard endpoint test failed: $($_.Exception.Message)"
        return $false
    }
    
    Write-Success "All tests passed!"
    return $true
}

function Remove-TemporaryFiles {
    Write-Info "Cleaning up temporary files..."
    
    Set-Location $TerraformDir
    if (Test-Path "tfplan") {
        Remove-Item "tfplan" -Force
    }
    
    Write-Success "Cleanup completed"
}

function Show-Help {
    Write-Host "AWS Deployment Script for MapReduce Project" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\deploy-aws.ps1 [OPTIONS]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Region REGION        AWS region (default: us-east-1)"
    Write-Host "  -Environment ENV       Environment (default: prod)"
    Write-Host "  -PlanOnly             Only run terraform plan (don't apply)"
    Write-Host "  -Force                Skip confirmation prompts"
    Write-Host "  -Test                 Run tests after deployment"
    Write-Host "  -Cleanup              Clean up resources"
    Write-Host "  -Help                 Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\deploy-aws.ps1                      # Deploy with default settings"
    Write-Host "  .\deploy-aws.ps1 -PlanOnly           # Only plan the deployment"
    Write-Host "  .\deploy-aws.ps1 -Region us-west-2   # Deploy to us-west-2 region"
    Write-Host "  .\deploy-aws.ps1 -Test               # Deploy and run tests"
    Write-Host "  .\deploy-aws.ps1 -Cleanup            # Clean up all resources"
}

# Main execution
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Info "Starting AWS deployment for MapReduce project..."
    Write-Info "Region: $Region"
    Write-Info "Environment: $Environment"
    
    if ($Cleanup) {
        Write-Info "Cleaning up AWS resources..."
        Set-Location $TerraformDir
        terraform destroy -auto-approve
        Write-Success "Cleanup completed"
        return
    }
    
    # Check prerequisites
    Test-Prerequisites
    
    # Setup Terraform
    Initialize-Terraform
    
    # Validate configuration
    Test-TerraformConfig
    
    # Plan deployment
    Invoke-TerraformPlan
    
    if ($PlanOnly) {
        Write-Success "Plan completed. Use -Force to apply changes."
        return
    }
    
    # Confirm deployment
    if (-not $Force) {
        Write-Host ""
        Write-Warning "This will create AWS resources that may incur costs."
        $Confirmation = Read-Host "Do you want to continue? (y/N)"
        if ($Confirmation -notmatch "^[Yy]$") {
            Write-Info "Deployment cancelled"
            return
        }
    }
    
    # Apply Terraform
    Invoke-TerraformApply
    
    # Get outputs
    Get-TerraformOutputs
    
    # Wait for health
    if (Wait-ForHealth) {
        Write-Success "Application is healthy and ready!"
    } else {
        Write-Error "Application failed to become healthy"
        exit 1
    }
    
    # Run tests if requested
    if ($Test) {
        if (Invoke-DeploymentTests) {
            Write-Success "All tests passed!"
        } else {
            Write-Error "Some tests failed"
            exit 1
        }
    }
    
    # Cleanup
    Remove-TemporaryFiles
    
    Write-Success "AWS deployment completed successfully!"
    Write-Host ""
    Write-Host "=== NEXT STEPS ===" -ForegroundColor Cyan
    Write-Host "1. Monitor your application in the AWS Console"
    Write-Host "2. Check CloudWatch logs for any issues"
    Write-Host "3. Configure monitoring and alerting as needed"
    Write-Host "4. Set up backup strategies for your S3 data"
    Write-Host ""
}

# Run main function
Main