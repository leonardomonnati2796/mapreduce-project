#!/bin/bash
# Script bash ottimizzato per gestione Docker cluster MapReduce
# Equivalente funzionale a docker-manager.ps1

set -e  # Exit on error

ACTION=${1:-"start"}
COMPOSE_FILE="docker/docker-compose.yml"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

check_docker() {
    if ! docker version >/dev/null 2>&1; then
        print_color $RED "ERRORE: Docker non è in esecuzione!"
        exit 1
    fi
}

check_files() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        print_color $RED "ERRORE: $COMPOSE_FILE non trovato!"
        exit 1
    fi
    
    if [[ ! -f "data/Words.txt" ]]; then
        print_color $RED "ERRORE: File di input data/Words.txt non trovato!"
        exit 1
    fi
}

start_cluster() {
    print_color $BLUE "=== AVVIO CLUSTER MAPREDUCE ==="
    echo
    
    # Controlli preliminari in parallelo
    check_docker &
    check_files &
    wait  # Attendi tutti i controlli
    
    echo "Avviando il cluster..."
    if docker compose -f "$COMPOSE_FILE" up -d --build; then
        print_color $GREEN "Cluster MapReduce avviato con successo!"
        echo "Dashboard: http://localhost:8080"
        
        # Attesa stabilizzazione e health check automatico
        echo "Attesa stabilizzazione cluster (10 secondi)..."
        sleep 10
        health_check
    else
        print_color $RED "Errore durante l'avvio del cluster"
        exit 1
    fi
}

start_cluster_fast() {
    print_color $GREEN "=== AVVIO RAPIDO CLUSTER MAPREDUCE ==="
    echo
    
    check_docker
    check_files
    
    echo "Avviando il cluster (modalità veloce - senza rebuild)..."
    if docker compose -f "$COMPOSE_FILE" up -d; then
        print_color $GREEN "Cluster MapReduce avviato con successo!"
        echo "Dashboard: http://localhost:8080"
        sleep 5
        health_check
    else
        print_color $RED "Errore durante l'avvio del cluster"
        exit 1
    fi
}

stop_cluster() {
    print_color $YELLOW "=== FERMATA CLUSTER MAPREDUCE ==="
    echo
    
    if docker compose -f "$COMPOSE_FILE" down; then
        print_color $GREEN "Cluster fermato con successo"
    else
        print_color $RED "Errore durante la fermata del cluster"
        exit 1
    fi
}

show_status() {
    print_color $BLUE "=== STATO CLUSTER MAPREDUCE ==="
    echo
    
    echo "Container:"
    docker compose -f "$COMPOSE_FILE" ps
    
    echo
    echo "Volumi:"
    docker volume ls | grep mapreduce || echo "Nessun volume mapreduce trovato"
    
    echo
    echo "Rete:"
    docker network ls | grep mapreduce || echo "Nessuna rete mapreduce trovata"
}

health_check() {
    print_color $CYAN "=== HEALTH CHECK CLUSTER ==="
    echo
    
    # Controllo container in parallelo
    {
        TOTAL=$(docker compose -f "$COMPOSE_FILE" ps --services | wc -l)
        RUNNING=$(docker compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
        
        if [[ $TOTAL -eq $RUNNING ]]; then
            print_color $GREEN "Tutti i container sono in esecuzione"
        else
            print_color $RED "Alcuni container non sono in esecuzione"
            docker compose -f "$COMPOSE_FILE" ps
        fi
    } &
    
    # Controllo dashboard in parallelo
    {
        echo "Verificando connettività di rete..."
        if curl -s --connect-timeout 3 http://localhost:8080 >/dev/null 2>&1; then
            print_color $GREEN "Dashboard accessibile su http://localhost:8080"
        else
            print_color $YELLOW "Dashboard non ancora accessibile"
        fi
    } &
    
    # Controlli health check master in parallelo
    {
        HEALTH_PORTS=(8100 8101 8102)
        ACTIVE_CHECKS=0
        
        for port in "${HEALTH_PORTS[@]}"; do
            {
                if curl -s --connect-timeout 2 "http://localhost:$port/health" >/dev/null 2>&1; then
                    print_color $GREEN "Master health check su porta $port: OK"
                    ((ACTIVE_CHECKS++))
                else
                    print_color $YELLOW "Master health check su porta $port non risponde"
                fi
            } &
        done
        
        wait  # Attendi tutti i controlli health
        
        if [[ $ACTIVE_CHECKS -gt 0 ]]; then
            print_color $GREEN "Raft cluster operativo ($ACTIVE_CHECKS master con health check attivi)"
        else
            print_color $RED "Raft cluster non operativo - nessun health check risponde"
        fi
    } &
    
    wait  # Attendi tutti i controlli
}

show_logs() {
    print_color $BLUE "=== LOG CLUSTER MAPREDUCE ==="
    echo
    echo "Premi Ctrl+C per uscire dai log"
    echo
    
    docker compose -f "$COMPOSE_FILE" logs -f
}

clean_all() {
    print_color $YELLOW "=== PULIZIA COMPLETA ==="
    
    echo "Fermando e rimuovendo container..."
    docker compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
    
    echo "Pulendo immagini..."
    docker image prune -f
    
    echo "Pulendo volumi..."
    docker volume prune -f
    
    print_color $GREEN "Pulizia completata"
}

copy_output() {
    print_color $BLUE "=== COPIA FILE DI OUTPUT DAL VOLUME DOCKER ==="
    echo
    
    check_docker
    
    # Trova un worker attivo
    WORKER_CONTAINER=$(docker compose -f "$COMPOSE_FILE" ps -q worker1 2>/dev/null | head -1)
    
    if [[ -z "$WORKER_CONTAINER" ]]; then
        print_color $RED "ERRORE: Nessun container worker attivo trovato"
        exit 1
    fi
    
    echo "Container worker attivo trovato: $WORKER_CONTAINER"
    
    # Crea directory output se non esiste
    mkdir -p data/output
    
    echo "Ricerca e copia file di output..."
    COPIED_FILES=0
    
    # Usa il numero di reducer corretto (3) invece di hardcoded 9
    for i in {0..2}; do
        if docker exec "$WORKER_CONTAINER" test -f "/tmp/mapreduce/mr-out-$i" 2>/dev/null; then
            if docker cp "$WORKER_CONTAINER:/tmp/mapreduce/mr-out-$i" "data/output/mr-out-$i"; then
                print_color $GREEN "File copiato: mr-out-$i"
                ((COPIED_FILES++))
            else
                print_color $RED "Errore copia file: mr-out-$i"
            fi
        fi
    done
    
    # Copia file finale unificato
    if docker exec "$WORKER_CONTAINER" test -f "/tmp/mapreduce/final-output.txt" 2>/dev/null; then
        if docker cp "$WORKER_CONTAINER:/tmp/mapreduce/final-output.txt" "data/output/final-output.txt"; then
            print_color $GREEN "File finale unificato copiato: final-output.txt"
            ((COPIED_FILES++))
        fi
    fi
    
    if [[ $COPIED_FILES -gt 0 ]]; then
        print_color $GREEN "Copiati $COPIED_FILES file di output in data/output/"
        echo "File nella cartella data/output:"
        ls -la data/output/
    else
        print_color $YELLOW "Nessun file di output trovato da copiare"
    fi
}

show_help() {
    print_color $CYAN "=== MapReduce Docker Manager (Bash) ==="
    echo
    echo "Usage: $0 [ACTION]"
    echo
    echo "Actions:"
    echo "  start       - Avvia il cluster MapReduce"
    echo "  start-fast  - Avvio rapido (senza rebuild)"
    echo "  stop        - Ferma tutti i container"
    echo "  restart     - Riavvia il cluster"
    echo "  status      - Mostra lo stato del cluster"
    echo "  logs        - Mostra i log dei container"
    echo "  health      - Controlla la salute del cluster"
    echo "  clean       - Pulisce tutto"
    echo "  copy-output - Copia file di output dai container"
    echo "  help        - Mostra questo messaggio"
    echo
}

# Main execution
case $ACTION in
    "start")
        start_cluster
        ;;
    "start-fast")
        start_cluster_fast
        ;;
    "stop")
        stop_cluster
        ;;
    "restart")
        stop_cluster
        sleep 3
        start_cluster
        ;;
    "status")
        show_status
        ;;
    "logs")
        show_logs
        ;;
    "health")
        health_check
        ;;
    "clean")
        clean_all
        ;;
    "copy-output")
        copy_output
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        print_color $RED "Azione non riconosciuta: $ACTION"
        show_help
        exit 1
        ;;
esac

echo
print_color $GREEN "=== Operazione completata ==="
