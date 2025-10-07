#!/bin/bash

# MapReduce AWS Deployment Setup Script
# Script completo per configurare e deployare il progetto su AWS

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzioni di utilità
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Controlla prerequisiti
check_prerequisites() {
    log_step "Controllando prerequisiti..."
    
    # Controlla AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI non installato"
        exit 1
    fi
    
    # Controlla Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform non installato"
        exit 1
    fi
    
    # Controlla credenziali AWS
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log_error "Credenziali AWS non configurate"
        exit 1
    fi
    
    # Controlla Docker
    if ! command -v docker &> /dev/null; then
        log_warn "Docker non installato (opzionale per test locali)"
    fi
    
    log_info "✅ Prerequisiti verificati"
}

# Crea key pair SSH
create_ssh_key_pair() {
    log_step "Configurando SSH key pair..."
    
    local key_name="mapreduce-key"
    local key_file="$HOME/.ssh/mapreduce-key.pem"
    
    # Controlla se la key pair esiste già
    if aws ec2 describe-key-pairs --key-names $key_name > /dev/null 2>&1; then
        log_info "✅ Key pair $key_name già esistente"
    else
        # Crea nuova key pair
        if [ ! -f "$key_file" ]; then
            log_info "Creando nuova key pair..."
            aws ec2 create-key-pair --key-name $key_name --query 'KeyMaterial' --output text > $key_file
            chmod 600 $key_file
            log_info "✅ Key pair creata: $key_file"
        else
            log_info "✅ Key pair già esistente: $key_file"
        fi
    fi
    
    # Ottieni la chiave pubblica
    local public_key=$(ssh-keygen -y -f $key_file 2>/dev/null || echo "")
    if [ -z "$public_key" ]; then
        log_error "Impossibile generare chiave pubblica da $key_file"
        exit 1
    fi
    
    echo "PUBLIC_KEY=\"$public_key\""
}

# Configura Terraform
setup_terraform() {
    log_step "Configurando Terraform..."
    
    cd aws/terraform/
    
    # Copia terraform.tfvars.example se non esiste
    if [ ! -f "terraform.tfvars" ]; then
        cp terraform.tfvars.example terraform.tfvars
        log_info "✅ File terraform.tfvars creato da template"
        log_warn "⚠️  IMPORTANTE: Modifica terraform.tfvars con i tuoi valori"
    else
        log_info "✅ File terraform.tfvars già esistente"
    fi
    
    # Inizializza Terraform
    terraform init
    log_info "✅ Terraform inizializzato"
}

# Valida configurazione Terraform
validate_terraform() {
    log_step "Validando configurazione Terraform..."
    
    cd aws/terraform/
    
    if terraform validate; then
        log_info "✅ Configurazione Terraform valida"
    else
        log_error "❌ Configurazione Terraform non valida"
        exit 1
    fi
}

# Pianifica deployment
plan_deployment() {
    log_step "Pianificando deployment..."
    
    cd aws/terraform/
    
    log_info "Eseguendo terraform plan..."
    terraform plan -out=tfplan
    
    log_info "✅ Piano di deployment creato"
    log_warn "⚠️  Rivedi il piano prima di procedere con l'applicazione"
}

# Applica deployment
apply_deployment() {
    log_step "Applicando deployment..."
    
    cd aws/terraform/
    
    log_info "Eseguendo terraform apply..."
    terraform apply tfplan
    
    log_info "✅ Deployment completato"
}

# Verifica deployment
verify_deployment() {
    log_step "Verificando deployment..."
    
    # Esegui script di verifica
    if [ -f "../scripts/verify-deployment.sh" ]; then
        chmod +x ../scripts/verify-deployment.sh
        ../scripts/verify-deployment.sh
    else
        log_warn "⚠️  Script di verifica non trovato"
    fi
}

# Mostra informazioni utili
show_deployment_info() {
    log_step "Informazioni deployment..."
    
    cd aws/terraform/
    
    echo ""
    log_info "🎉 Deployment completato!"
    echo ""
    
    # Mostra output Terraform
    log_info "Informazioni istanze:"
    terraform output master_instances
    terraform output worker_instances
    
    echo ""
    log_info "Load Balancer DNS:"
    terraform output load_balancer_dns
    
    echo ""
    log_info "Bucket S3:"
    terraform output s3_bucket_name
    
    echo ""
    log_info "📋 Prossimi passi:"
    echo "1. Carica file di input su S3:"
    echo "   aws s3 cp data/Words.txt s3://\$(terraform output -raw s3_bucket_name)/data/"
    echo ""
    echo "2. Accedi al dashboard:"
    echo "   http://\$(terraform output -raw load_balancer_dns)"
    echo ""
    echo "3. Verifica le istanze:"
    echo "   ./scripts/verify-deployment.sh"
}

# Cleanup (rimuove tutto)
cleanup_deployment() {
    log_step "Rimuovendo deployment..."
    
    cd aws/terraform/
    
    log_warn "⚠️  ATTENZIONE: Questa operazione rimuoverà TUTTE le risorse AWS create!"
    read -p "Sei sicuro di voler continuare? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        terraform destroy -auto-approve
        log_info "✅ Deployment rimosso"
    else
        log_info "Operazione annullata"
    fi
}

# Funzione principale
main() {
    echo "🚀 MapReduce AWS Deployment Setup"
    echo "=================================="
    echo ""
    
    check_prerequisites
    setup_terraform
    validate_terraform
    plan_deployment
    
    echo ""
    log_warn "⚠️  ATTENZIONE: Il deployment creerà risorse AWS che potrebbero generare costi!"
    read -p "Vuoi procedere con l'applicazione? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy]es$ ]]; then
        apply_deployment
        verify_deployment
        show_deployment_info
    else
        log_info "Deployment annullato"
    fi
}

# Gestione degli argomenti
case "${1:-}" in
    "setup")
        check_prerequisites
        setup_terraform
        ;;
    "validate")
        validate_terraform
        ;;
    "plan")
        plan_deployment
        ;;
    "apply")
        apply_deployment
        verify_deployment
        show_deployment_info
        ;;
    "verify")
        verify_deployment
        ;;
    "cleanup")
        cleanup_deployment
        ;;
    "key")
        create_ssh_key_pair
        ;;
    *)
        main
        ;;
esac
