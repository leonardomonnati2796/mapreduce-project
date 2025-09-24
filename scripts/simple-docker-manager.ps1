# Script PowerShell semplificato per la gestione del cluster Docker MapReduce

param(
    [Parameter(Position=0)]
    [string]$Action = "start",
    
    [switch]$Help
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-ColorOutput "=== MapReduce Docker Manager ===" "Cyan"
    Write-Host ""
    Write-Host "Usage: .\scripts\simple-docker-manager.ps1 [ACTION]"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  start       - Avvia il cluster MapReduce"
    Write-Host "  stop        - Ferma tutti i container"
    Write-Host "  restart     - Riavvia il cluster"
    Write-Host "  status      - Mostra lo stato del cluster"
    Write-Host "  logs        - Mostra i log dei container"
    Write-Host "  health      - Controlla la salute del cluster"
    Write-Host "  clean       - Pulisce tutto"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non è in esecuzione!" "Red"
        return $false
    }
}

function Start-Cluster {
    Write-ColorOutput "=== AVVIO CLUSTER MAPREDUCE ===" "Blue"
    
    if (-not (Test-DockerRunning)) {
        return $false
    }
    
    Write-Host "Avviando il cluster..."
    docker-compose -f docker/docker-compose.yml up -d --build
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Cluster avviato con successo!" "Green"
        Write-Host "Dashboard: http://localhost:8080"
        return $true
    } else {
        Write-ColorOutput "Errore durante l'avvio del cluster" "Red"
        return $false
    }
}

function Stop-Cluster {
    Write-ColorOutput "=== FERMATA CLUSTER MAPREDUCE ===" "Yellow"
    
    docker-compose -f docker/docker-compose.yml down
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Cluster fermato con successo" "Green"
    } else {
        Write-ColorOutput "Errore durante la fermata del cluster" "Red"
    }
}

function Show-Status {
    Write-ColorOutput "=== STATO CLUSTER MAPREDUCE ===" "Blue"
    Write-Host ""
    
    Write-Host "Container:"
    docker-compose -f docker/docker-compose.yml ps
}

function Show-Logs {
    Write-ColorOutput "=== LOG CLUSTER MAPREDUCE ===" "Blue"
    Write-Host "Premi Ctrl+C per uscire dai log"
    Write-Host ""
    
    docker-compose -f docker/docker-compose.yml logs -f
}

function Test-Health {
    Write-ColorOutput "=== HEALTH CHECK CLUSTER ===" "Cyan"
    
    $containers = docker-compose -f docker/docker-compose.yml ps --services
    $runningContainers = docker-compose -f docker/docker-compose.yml ps --services --filter "status=running"
    
    if ($containers.Count -eq $runningContainers.Count) {
        Write-ColorOutput "Tutti i container sono in esecuzione" "Green"
    } else {
        Write-ColorOutput "Alcuni container non sono in esecuzione" "Red"
    }
}

function Clean-All {
    Write-ColorOutput "=== PULIZIA COMPLETA ===" "Yellow"
    
    Write-Host "Fermando e rimuovendo container..."
    docker-compose -f docker/docker-compose.yml down --volumes --remove-orphans
    
    Write-Host "Pulendo immagini..."
    docker image prune -f
    
    Write-Host "Pulendo volumi..."
    docker volume prune -f
    
    Write-ColorOutput "Pulizia completata" "Green"
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

Write-ColorOutput "=== MAPREDUCE DOCKER MANAGER ===" "Blue"
Write-Host "Azione: $Action"
Write-Host ""

if (-not (Test-DockerRunning)) {
    exit 1
}

switch ($Action.ToLower()) {
    "start" {
        Start-Cluster
    }
    "stop" {
        Stop-Cluster
    }
    "restart" {
        Stop-Cluster
        Start-Sleep -Seconds 3
        Start-Cluster
    }
    "status" {
        Show-Status
    }
    "logs" {
        Show-Logs
    }
    "health" {
        Test-Health
    }
    "clean" {
        Clean-All
    }
    default {
        Write-ColorOutput "Azione non riconosciuta: $Action" "Red"
        Show-Help
        exit 1
    }
}

Write-Host ""
Write-ColorOutput "=== Operazione completata ===" "Green"
