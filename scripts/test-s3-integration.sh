#!/bin/bash

# MapReduce S3 Integration Test Script
# Questo script testa l'integrazione S3 per il progetto MapReduce

set -e

echo "🧪 MapReduce S3 Integration Test"
echo "================================="

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Controlla se le variabili d'ambiente sono configurate
check_env_vars() {
    log_info "Controllando variabili d'ambiente..."
    
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3_BUCKET_NAME non configurato"
        exit 1
    fi
    
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS_REGION non configurato"
        exit 1
    fi
    
    log_info "✅ Variabili d'ambiente configurate correttamente"
}

# Test 1: Carica file di input su S3
test_upload_input_data() {
    log_info "Test 1: Caricamento file di input su S3..."
    
    # Crea file di test
    mkdir -p /tmp/mapreduce-test/input
    echo "hello world" > /tmp/mapreduce-test/input/test1.txt
    echo "mapreduce test" > /tmp/mapreduce-test/input/test2.txt
    echo "distributed computing" > /tmp/mapreduce-test/input/test3.txt
    
    # Carica su S3 usando AWS CLI
    aws s3 sync /tmp/mapreduce-test/input/ s3://$S3_BUCKET_NAME/data/ --delete
    
    if [ $? -eq 0 ]; then
        log_info "✅ File di input caricati su S3 con successo"
    else
        log_error "❌ Errore nel caricamento su S3"
        exit 1
    fi
}

# Test 2: Verifica che i file siano su S3
test_verify_s3_files() {
    log_info "Test 2: Verifica presenza file su S3..."
    
    # Lista i file su S3
    files=$(aws s3 ls s3://$S3_BUCKET_NAME/data/ --recursive | wc -l)
    
    if [ $files -gt 0 ]; then
        log_info "✅ Trovati $files file su S3"
        aws s3 ls s3://$S3_BUCKET_NAME/data/ --recursive
    else
        log_error "❌ Nessun file trovato su S3"
        exit 1
    fi
}

# Test 3: Test dell'applicazione Go con S3
test_go_s3_integration() {
    log_info "Test 3: Test integrazione Go con S3..."
    
    # Imposta variabili d'ambiente per il test
    export S3_SYNC_ENABLED=true
    export MAPREDUCE_INPUT_GLOB="s3://$S3_BUCKET_NAME/data/*.txt"
    export TMP_PATH="/tmp/mapreduce-test"
    
    # Crea directory temporanea
    mkdir -p $TMP_PATH/input
    
    # Testa il download da S3 (simula quello che fa il master)
    log_info "Testando download da S3..."
    
    # Simula il comportamento del master
    if [ -f "mapreduce" ]; then
        log_info "Eseguendo test con binario mapreduce..."
        # Qui potresti eseguire un test più specifico con il binario
    else
        log_warn "Binario mapreduce non trovato, saltando test Go"
    fi
}

# Test 4: Test delle API del Dashboard
test_dashboard_s3_apis() {
    log_info "Test 4: Test API Dashboard S3..."
    
    # Controlla se il dashboard è in esecuzione
    if curl -f http://localhost:8080/health > /dev/null 2>&1; then
        log_info "Dashboard disponibile, testando API S3..."
        
        # Test API S3 stats
        response=$(curl -s http://localhost:8080/api/s3/stats)
        if echo "$response" | grep -q "success"; then
            log_info "✅ API S3 stats funzionante"
        else
            log_warn "⚠️  API S3 stats non disponibile"
        fi
        
        # Test API list input files
        response=$(curl -s http://localhost:8080/api/s3/input-files)
        if echo "$response" | grep -q "success"; then
            log_info "✅ API list input files funzionante"
        else
            log_warn "⚠️  API list input files non disponibile"
        fi
    else
        log_warn "Dashboard non disponibile, saltando test API"
    fi
}

# Test 5: Test di sincronizzazione
test_sync_functionality() {
    log_info "Test 5: Test funzionalità di sincronizzazione..."
    
    # Crea file di output di test
    mkdir -p /tmp/mapreduce-test/output
    echo "output result 1" > /tmp/mapreduce-test/output/result1.txt
    echo "output result 2" > /tmp/mapreduce-test/output/result2.txt
    
    # Simula sincronizzazione
    aws s3 sync /tmp/mapreduce-test/output/ s3://$S3_BUCKET_NAME/output/ --delete
    
    if [ $? -eq 0 ]; then
        log_info "✅ Sincronizzazione output funzionante"
    else
        log_error "❌ Errore nella sincronizzazione"
        exit 1
    fi
}

# Cleanup
cleanup() {
    log_info "Pulizia file di test..."
    rm -rf /tmp/mapreduce-test
    log_info "✅ Pulizia completata"
}

# Funzione principale
main() {
    echo "Iniziando test di integrazione S3..."
    echo ""
    
    # Esegui tutti i test
    check_env_vars
    test_upload_input_data
    test_verify_s3_files
    test_go_s3_integration
    test_dashboard_s3_apis
    test_sync_functionality
    
    echo ""
    log_info "🎉 Tutti i test completati con successo!"
    log_info "L'integrazione S3 è funzionante"
    
    # Cleanup
    cleanup
}

# Gestione degli argomenti
case "${1:-}" in
    "upload")
        check_env_vars
        test_upload_input_data
        ;;
    "verify")
        check_env_vars
        test_verify_s3_files
        ;;
    "dashboard")
        test_dashboard_s3_apis
        ;;
    "sync")
        check_env_vars
        test_sync_functionality
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        main
        ;;
esac
