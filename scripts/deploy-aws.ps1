# Script di deployment per MapReduce su AWS (PowerShell)
param(
    [Parameter(Position=0)]
    [ValidateSet("plan", "deploy", "destroy", "status")]
    [string]$Action = "deploy",
    
    [string]$AWSRegion = "us-east-1",
    [string]$ProjectName = "mapreduce"
)

# Configurazione
$ErrorActionPreference = "Stop"
$TERRAFORM_DIR = "aws/terraform"
$DOCKER_DIR = "docker"

# Funzioni di logging
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

# Verifica prerequisiti
function Test-Prerequisites {
    Write-Info "Verificando prerequisiti..."
    
    # Verifica AWS CLI
    try {
        aws --version | Out-Null
    } catch {
        Write-Error "AWS CLI non trovato. Installalo prima di continuare."
        exit 1
    }
    
    # Verifica Terraform
    try {
        terraform --version | Out-Null
    } catch {
        Write-Error "Terraform non trovato. Installalo prima di continuare."
        exit 1
    }
    
    # Verifica Docker
    try {
        docker --version | Out-Null
    } catch {
        Write-Error "Docker non trovato. Installalo prima di continuare."
        exit 1
    }
    
    # Verifica Docker Compose
    try {
        docker-compose --version | Out-Null
    } catch {
        Write-Error "Docker Compose non trovato. Installalo prima di continuare."
        exit 1
    }
    
    # Verifica credenziali AWS
    try {
        aws sts get-caller-identity | Out-Null
    } catch {
        Write-Error "Credenziali AWS non configurate. Configura AWS CLI prima di continuare."
        exit 1
    }
    
    Write-Success "Tutti i prerequisiti sono soddisfatti"
}

# Inizializza Terraform
function Initialize-Terraform {
    Write-Info "Inizializzando Terraform..."
    Push-Location $TERRAFORM_DIR
    
    try {
        terraform init
        terraform validate
        Write-Success "Terraform inizializzato correttamente"
    } finally {
        Pop-Location
    }
}

# Pianifica deployment
function Plan-Deployment {
    Write-Info "Pianificando deployment..."
    Push-Location $TERRAFORM_DIR
    
    try {
        terraform plan -out=tfplan
        Write-Success "Piano di deployment creato"
    } finally {
        Pop-Location
    }
}

# Esegue deployment
function Deploy-Infrastructure {
    Write-Info "Deploying infrastruttura AWS..."
    Push-Location $TERRAFORM_DIR
    
    try {
        terraform apply tfplan
        Write-Success "Infrastruttura deployata correttamente"
    } finally {
        Pop-Location
    }
}

# Ottiene output di Terraform
function Get-TerraformOutputs {
    Write-Info "Ottenendo output di Terraform..."
    Push-Location $TERRAFORM_DIR
    
    try {
        $ALB_DNS = terraform output -raw load_balancer_dns
        $S3_BUCKET = terraform output -raw s3_bucket_name
        $VPC_ID = terraform output -raw vpc_id
        
        Write-Success "Output ottenuti:"
        Write-Info "Load Balancer DNS: $ALB_DNS"
        Write-Info "S3 Bucket: $S3_BUCKET"
        Write-Info "VPC ID: $VPC_ID"
        
        return @{
            ALB_DNS = $ALB_DNS
            S3_BUCKET = $S3_BUCKET
            VPC_ID = $VPC_ID
        }
    } finally {
        Pop-Location
    }
}

# Builda le immagini Docker
function Build-DockerImages {
    Write-Info "Building immagini Docker..."
    
    # Build dell'immagine principale
    docker build -f "$DOCKER_DIR/Dockerfile.aws" -t "$ProjectName`:latest" .
    
    Write-Success "Immagini Docker buildate correttamente"
}

# Crea file di configurazione per deployment
function New-DeploymentConfig {
    param($Outputs)
    
    Write-Info "Creando configurazione di deployment..."
    
    $envContent = @"
# AWS Configuration
AWS_REGION=$AWSRegion
AWS_S3_BUCKET=$($Outputs.S3_BUCKET)

# Load Balancer
ALB_DNS=$($Outputs.ALB_DNS)

# MapReduce Configuration
RAFT_ADDRESSES=master0:1234,master1:1234,master2:1234
RPC_ADDRESSES=master0:8000,master1:8001,master2:8002
TMP_PATH=/tmp/mapreduce

# Performance Settings
METRICS_ENABLED=true
METRICS_PORT=9090
MAPREDUCE_MASTER_TASK_TIMEOUT=300s
MAPREDUCE_MASTER_HEARTBEAT_INTERVAL=10s
MAPREDUCE_WORKER_RETRY_INTERVAL=5s

# Health Check Settings
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_INTERVAL=30s
HEALTH_CHECK_TIMEOUT=10s

# S3 Sync Settings
S3_SYNC_ENABLED=true
S3_SYNC_INTERVAL=60s
S3_BACKUP_ENABLED=true
"@
    
    $envContent | Out-File -FilePath ".env.aws" -Encoding UTF8
    Write-Success "Configurazione creata in .env.aws"
}

# Testa il deployment
function Test-Deployment {
    param($Outputs)
    
    Write-Info "Testando deployment..."
    
    # Attendi che i servizi siano pronti
    Write-Info "Attendendo che i servizi siano pronti..."
    Start-Sleep -Seconds 60
    
    # Test health check
    try {
        $response = Invoke-WebRequest -Uri "http://$($Outputs.ALB_DNS)/health" -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Success "Health check superato"
        }
    } catch {
        Write-Warning "Health check fallito - i servizi potrebbero non essere ancora pronti"
    }
    
    # Test dashboard
    try {
        $response = Invoke-WebRequest -Uri "http://$($Outputs.ALB_DNS)" -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Success "Dashboard accessibile"
        }
    } catch {
        Write-Warning "Dashboard non accessibile - verifica la configurazione"
    }
}

# Mostra informazioni finali
function Show-DeploymentInfo {
    param($Outputs)
    
    Write-Success "Deployment completato!"
    Write-Host ""
    Write-Info "Informazioni di accesso:"
    Write-Host "  Dashboard: http://$($Outputs.ALB_DNS)" -ForegroundColor Cyan
    Write-Host "  Health Check: http://$($Outputs.ALB_DNS)/health" -ForegroundColor Cyan
    Write-Host "  S3 Bucket: $($Outputs.S3_BUCKET)" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "Comandi utili:"
    Write-Host "  Verifica stato: aws ec2 describe-instances --filters 'Name=tag:Name,Values=*mapreduce*'" -ForegroundColor Gray
    Write-Host "  Logs: aws logs describe-log-groups --log-group-name-prefix '/aws/ec2/mapreduce'" -ForegroundColor Gray
    Write-Host "  S3: aws s3 ls s3://$($Outputs.S3_BUCKET)" -ForegroundColor Gray
    Write-Host ""
    Write-Info "Per distruggere l'infrastruttura:"
    Write-Host "  cd $TERRAFORM_DIR && terraform destroy" -ForegroundColor Gray
}

# Funzione principale
function Start-Deployment {
    Write-Info "Iniziando deployment di MapReduce su AWS..."
    
    Test-Prerequisites
    Initialize-Terraform
    Plan-Deployment
    
    # Chiedi conferma
    Write-Host ""
    Write-Warning "Stai per deployare l'infrastruttura AWS. Questo potrebbe comportare costi."
    $confirmation = Read-Host "Vuoi continuare? (y/N)"
    if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
        Write-Info "Deployment annullato"
        return
    }
    
    Deploy-Infrastructure
    $outputs = Get-TerraformOutputs
    Build-DockerImages
    New-DeploymentConfig -Outputs $outputs
    Test-Deployment -Outputs $outputs
    Show-DeploymentInfo -Outputs $outputs
}

# Gestione degli argomenti
switch ($Action) {
    "plan" {
        Test-Prerequisites
        Initialize-Terraform
        Plan-Deployment
    }
    "deploy" {
        Start-Deployment
    }
    "destroy" {
        Write-Warning "Stai per distruggere l'infrastruttura AWS."
        $confirmation = Read-Host "Sei sicuro? (y/N)"
        if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
            Push-Location $TERRAFORM_DIR
            try {
                terraform destroy
                Write-Success "Infrastruttura distrutta"
            } finally {
                Pop-Location
            }
        } else {
            Write-Info "Operazione annullata"
        }
    }
    "status" {
        Push-Location $TERRAFORM_DIR
        try {
            terraform output
        } finally {
            Pop-Location
        }
    }
}
