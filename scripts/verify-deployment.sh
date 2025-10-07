#!/bin/bash

# MapReduce AWS Deployment Verification Script
# Verifica che tutte le istanze siano create e configurate correttamente

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

# Controlla le credenziali AWS
check_aws_credentials() {
    log_step "Controllando credenziali AWS..."
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        log_error "Credenziali AWS non configurate"
        exit 1
    fi
    
    log_info "✅ Credenziali AWS configurate"
}

# Conta le istanze per tipo
count_instances() {
    local instance_type=$1
    local count=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=mapreduce" \
                 "Name=tag:Type,Values=$instance_type" \
                 "Name=instance-state-name,Values=running" \
        --query 'length(Reservations[].Instances[])')
    echo $count
}

# Verifica il numero di istanze
verify_instance_count() {
    log_step "Verificando numero di istanze..."
    
    local master_count=$(count_instances "master")
    local worker_count=$(count_instances "worker")
    local total_count=$((master_count + worker_count))
    
    log_info "Istanze Master: $master_count"
    log_info "Istanze Worker: $worker_count"
    log_info "Totale Istanze: $total_count"
    
    if [ $master_count -eq 3 ] && [ $worker_count -eq 3 ]; then
        log_info "✅ Numero corretto di istanze (3 master + 3 worker = 6 totali)"
    else
        log_error "❌ Numero errato di istanze. Atteso: 3 master + 3 worker, Trovato: $master_count master + $worker_count worker"
        return 1
    fi
}

# Lista le istanze con dettagli
list_instances() {
    log_step "Listando istanze create..."
    
    aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=mapreduce" \
                 "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].{
            Name:Tags[?Key==`Name`].Value|[0],
            Type:Tags[?Key==`Type`].Value|[0],
            PublicIP:PublicIpAddress,
            PrivateIP:PrivateIpAddress,
            State:State.Name
        }' \
        --output table
}

# Verifica la configurazione delle istanze
verify_instance_configuration() {
    log_step "Verificando configurazione istanze..."
    
    # Ottieni le istanze
    local instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=mapreduce" \
                 "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].{
            Name:Tags[?Key==`Name`].Value|[0],
            PublicIP:PublicIpAddress,
            Type:Tags[?Key==`Type`].Value|[0]
        }' \
        --output json)
    
    # Verifica ogni istanza
    echo "$instances" | jq -r '.[] | @base64' | while read -r instance; do
        local decoded=$(echo "$instance" | base64 -d)
        local name=$(echo "$decoded" | jq -r '.Name')
        local public_ip=$(echo "$decoded" | jq -r '.PublicIP')
        local type=$(echo "$decoded" | jq -r '.Type')
        
        if [ "$public_ip" != "null" ] && [ "$public_ip" != "" ]; then
            log_info "Verificando $name ($type) su $public_ip..."
            
            # Test SSH (se key pair configurato)
            if [ -f ~/.ssh/mapreduce-key.pem ]; then
                if ssh -i ~/.ssh/mapreduce-key.pem -o ConnectTimeout=10 -o StrictHostKeyChecking=no ec2-user@$public_ip "echo 'SSH OK'" > /dev/null 2>&1; then
                    log_info "✅ SSH funzionante per $name"
                    
                    # Verifica Docker
                    if ssh -i ~/.ssh/mapreduce-key.pem ec2-user@$public_ip "sudo docker ps" > /dev/null 2>&1; then
                        log_info "✅ Docker funzionante per $name"
                        
                        # Verifica container specifici
                        if [ "$type" = "master" ]; then
                            if ssh -i ~/.ssh/mapreduce-key.pem ec2-user@$public_ip "sudo docker ps | grep mapreduce-master" > /dev/null 2>&1; then
                                log_info "✅ Container master attivo per $name"
                            else
                                log_warn "⚠️  Container master non trovato per $name"
                            fi
                        elif [ "$type" = "worker" ]; then
                            if ssh -i ~/.ssh/mapreduce-key.pem ec2-user@$public_ip "sudo docker ps | grep mapreduce-worker" > /dev/null 2>&1; then
                                log_info "✅ Container worker attivo per $name"
                            else
                                log_warn "⚠️  Container worker non trovato per $name"
                            fi
                        fi
                    else
                        log_warn "⚠️  Docker non funzionante per $name"
                    fi
                else
                    log_warn "⚠️  SSH non funzionante per $name"
                fi
            else
                log_warn "⚠️  Key pair SSH non trovato, saltando test SSH"
            fi
        else
            log_warn "⚠️  IP pubblico non disponibile per $name"
        fi
    done
}

# Verifica S3 bucket
verify_s3_bucket() {
    log_step "Verificando bucket S3..."
    
    # Ottieni il nome del bucket da Terraform output
    local bucket_name=$(cd aws/terraform && terraform output -raw s3_bucket_name 2>/dev/null || echo "")
    
    if [ -z "$bucket_name" ]; then
        log_warn "⚠️  Nome bucket S3 non trovato in Terraform output"
        return
    fi
    
    log_info "Bucket S3: $bucket_name"
    
    # Verifica che il bucket esista
    if aws s3 ls s3://$bucket_name > /dev/null 2>&1; then
        log_info "✅ Bucket S3 accessibile"
        
        # Lista contenuto
        local file_count=$(aws s3 ls s3://$bucket_name/ --recursive | wc -l)
        log_info "File nel bucket: $file_count"
        
        if [ $file_count -gt 0 ]; then
            log_info "✅ Bucket S3 contiene file"
        else
            log_warn "⚠️  Bucket S3 vuoto"
        fi
    else
        log_error "❌ Bucket S3 non accessibile"
    fi
}

# Verifica Load Balancer
verify_load_balancer() {
    log_step "Verificando Load Balancer..."
    
    # Ottieni DNS del Load Balancer
    local lb_dns=$(cd aws/terraform && terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    
    if [ -z "$lb_dns" ]; then
        log_warn "⚠️  DNS Load Balancer non trovato in Terraform output"
        return
    fi
    
    log_info "Load Balancer DNS: $lb_dns"
    
    # Test health check
    if curl -f http://$lb_dns/health > /dev/null 2>&1; then
        log_info "✅ Load Balancer health check funzionante"
    else
        log_warn "⚠️  Load Balancer health check non funzionante"
    fi
}

# Test completo del sistema
test_system_functionality() {
    log_step "Testando funzionalità del sistema..."
    
    # Ottieni DNS del Load Balancer
    local lb_dns=$(cd aws/terraform && terraform output -raw load_balancer_dns 2>/dev/null || echo "")
    
    if [ -z "$lb_dns" ]; then
        log_warn "⚠️  DNS Load Balancer non disponibile, saltando test sistema"
        return
    fi
    
    # Test dashboard
    if curl -f http://$lb_dns/ > /dev/null 2>&1; then
        log_info "✅ Dashboard accessibile"
    else
        log_warn "⚠️  Dashboard non accessibile"
    fi
    
    # Test API S3
    if curl -f http://$lb_dns/api/s3/stats > /dev/null 2>&1; then
        log_info "✅ API S3 funzionante"
    else
        log_warn "⚠️  API S3 non funzionante"
    fi
}

# Funzione principale
main() {
    echo "🔍 MapReduce AWS Deployment Verification"
    echo "========================================"
    echo ""
    
    check_aws_credentials
    verify_instance_count
    list_instances
    verify_instance_configuration
    verify_s3_bucket
    verify_load_balancer
    test_system_functionality
    
    echo ""
    log_info "🎉 Verifica completata!"
    log_info "Per maggiori dettagli, consulta i log delle istanze"
}

# Gestione degli argomenti
case "${1:-}" in
    "instances")
        check_aws_credentials
        verify_instance_count
        list_instances
        ;;
    "config")
        check_aws_credentials
        verify_instance_configuration
        ;;
    "s3")
        check_aws_credentials
        verify_s3_bucket
        ;;
    "lb")
        verify_load_balancer
        ;;
    "test")
        test_system_functionality
        ;;
    *)
        main
        ;;
esac
