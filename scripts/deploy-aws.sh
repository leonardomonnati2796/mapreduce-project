#!/bin/bash

# Script di deployment per MapReduce su AWS
set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzioni di logging
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

# Configurazione
PROJECT_NAME="mapreduce"
AWS_REGION="${AWS_REGION:-us-east-1}"
TERRAFORM_DIR="aws/terraform"
DOCKER_DIR="docker"

# Verifica prerequisiti
check_prerequisites() {
    log_info "Verificando prerequisiti..."
    
    # Verifica AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI non trovato. Installalo prima di continuare."
        exit 1
    fi
    
    # Verifica Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform non trovato. Installalo prima di continuare."
        exit 1
    fi
    
    # Verifica Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker non trovato. Installalo prima di continuare."
        exit 1
    fi
    
    # Verifica Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose non trovato. Installalo prima di continuare."
        exit 1
    fi
    
    # Verifica credenziali AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Credenziali AWS non configurate. Configura AWS CLI prima di continuare."
        exit 1
    fi
    
    log_success "Tutti i prerequisiti sono soddisfatti"
}

# Inizializza Terraform
init_terraform() {
    log_info "Inizializzando Terraform..."
    cd $TERRAFORM_DIR
    
    terraform init
    terraform validate
    
    log_success "Terraform inizializzato correttamente"
    cd - > /dev/null
}

# Pianifica deployment
plan_deployment() {
    log_info "Pianificando deployment..."
    cd $TERRAFORM_DIR
    
    terraform plan -out=tfplan
    
    log_success "Piano di deployment creato"
    cd - > /dev/null
}

# Esegue deployment
deploy_infrastructure() {
    log_info "Deploying infrastruttura AWS..."
    cd $TERRAFORM_DIR
    
    terraform apply tfplan
    
    log_success "Infrastruttura deployata correttamente"
    cd - > /dev/null
}

# Ottiene output di Terraform
get_terraform_outputs() {
    log_info "Ottenendo output di Terraform..."
    cd $TERRAFORM_DIR
    
    ALB_DNS=$(terraform output -raw load_balancer_dns)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    VPC_ID=$(terraform output -raw vpc_id)
    
    log_success "Output ottenuti:"
    log_info "Load Balancer DNS: $ALB_DNS"
    log_info "S3 Bucket: $S3_BUCKET"
    log_info "VPC ID: $VPC_ID"
    
    cd - > /dev/null
}

# Builda le immagini Docker
build_docker_images() {
    log_info "Building immagini Docker..."
    
    # Build dell'immagine principale
    docker build -f $DOCKER_DIR/Dockerfile.aws -t $PROJECT_NAME:latest .
    
    log_success "Immagini Docker buildate correttamente"
}

# Crea file di configurazione per deployment
create_deployment_config() {
    log_info "Creando configurazione di deployment..."
    
    cat > .env.aws << EOF
# AWS Configuration
AWS_REGION=$AWS_REGION
AWS_S3_BUCKET=$S3_BUCKET

# Load Balancer
ALB_DNS=$ALB_DNS

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
EOF
    
    log_success "Configurazione creata in .env.aws"
}

# Testa il deployment
test_deployment() {
    log_info "Testando deployment..."
    
    # Attendi che i servizi siano pronti
    log_info "Attendendo che i servizi siano pronti..."
    sleep 60
    
    # Test health check
    if curl -f "http://$ALB_DNS/health" &> /dev/null; then
        log_success "Health check superato"
    else
        log_warning "Health check fallito - i servizi potrebbero non essere ancora pronti"
    fi
    
    # Test dashboard
    if curl -f "http://$ALB_DNS" &> /dev/null; then
        log_success "Dashboard accessibile"
    else
        log_warning "Dashboard non accessibile - verifica la configurazione"
    fi
}

# Mostra informazioni finali
show_deployment_info() {
    log_success "Deployment completato!"
    echo
    log_info "Informazioni di accesso:"
    echo "  Dashboard: http://$ALB_DNS"
    echo "  Health Check: http://$ALB_DNS/health"
    echo "  S3 Bucket: $S3_BUCKET"
    echo
    log_info "Comandi utili:"
    echo "  Verifica stato: aws ec2 describe-instances --filters 'Name=tag:Name,Values=*mapreduce*'"
    echo "  Logs: aws logs describe-log-groups --log-group-name-prefix '/aws/ec2/mapreduce'"
    echo "  S3: aws s3 ls s3://$S3_BUCKET"
    echo
    log_info "Per distruggere l'infrastruttura:"
    echo "  cd $TERRAFORM_DIR && terraform destroy"
}

# Funzione principale
main() {
    log_info "Iniziando deployment di MapReduce su AWS..."
    
    check_prerequisites
    init_terraform
    plan_deployment
    
    # Chiedi conferma
    echo
    log_warning "Stai per deployare l'infrastruttura AWS. Questo potrebbe comportare costi."
    read -p "Vuoi continuare? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment annullato"
        exit 0
    fi
    
    deploy_infrastructure
    get_terraform_outputs
    build_docker_images
    create_deployment_config
    test_deployment
    show_deployment_info
}

# Gestione degli argomenti
case "${1:-}" in
    "plan")
        check_prerequisites
        init_terraform
        plan_deployment
        ;;
    "deploy")
        main
        ;;
    "destroy")
        log_warning "Stai per distruggere l'infrastruttura AWS."
        read -p "Sei sicuro? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd $TERRAFORM_DIR
            terraform destroy
            cd - > /dev/null
            log_success "Infrastruttura distrutta"
        else
            log_info "Operazione annullata"
        fi
        ;;
    "status")
        cd $TERRAFORM_DIR
        terraform output
        cd - > /dev/null
        ;;
    *)
        echo "Usage: $0 {plan|deploy|destroy|status}"
        echo
        echo "Commands:"
        echo "  plan    - Pianifica il deployment senza eseguirlo"
        echo "  deploy  - Esegue il deployment completo"
        echo "  destroy - Distrugge l'infrastruttura"
        echo "  status  - Mostra lo stato dell'infrastruttura"
        exit 1
        ;;
esac
