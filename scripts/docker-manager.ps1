# Script PowerShell unificato per la gestione del cluster Docker MapReduce
# Combina semplicità e funzionalità avanzate

param(
    [Parameter(Position=0)]
    [string]$Action = "start",
    
    [switch]$Clean,
    [switch]$Build,
    [switch]$Logs,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Restart,
    [switch]$Scale,
    [int]$Workers = 2,
    [int]$Masters = 3,
    [switch]$HealthCheck,
    [switch]$FaultTest,
    [switch]$Backup,
    [switch]$Recover,
    [switch]$CopyOutput,
    [switch]$Help
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-ColorOutput "=== MapReduce Docker Manager ===" "Cyan"
    Write-Host ""
    Write-Host "Usage: .\scripts\docker-manager.ps1 [ACTION]"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  start       - Avvia il cluster MapReduce"
    Write-Host "  stop        - Ferma tutti i container"
    Write-Host "  restart     - Riavvia il cluster"
    Write-Host "  status      - Mostra lo stato del cluster"
    Write-Host "  logs        - Mostra i log dei container"
    Write-Host "  health      - Controlla la salute del cluster"
    Write-Host "  clean       - Pulisce tutto"
    Write-Host "  dashboard   - Apre il dashboard nel browser"
    Write-Host "  backup      - Crea backup dei dati"
    Write-Host "  copy-output - Copia file di output dai container"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Clean          Pulisce tutti i container e volumi esistenti"
    Write-Host "  -Build          Ricostruisce le immagini Docker"
    Write-Host "  -FaultTest      Testa la fault tolerance del cluster"
    Write-Host "  -CopyOutput     Copia file di output dai container alla cartella locale"
    Write-Host "  -Help           Mostra questo messaggio di aiuto"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non e in esecuzione!" "Red"
        Write-Host "Assicurati che Docker Desktop sia avviato e riprova."
        return $false
    }
}

function Start-Cluster {
    Write-ColorOutput "=== AVVIO CLUSTER MAPREDUCE ===" "Blue"
    Write-Host ""
    
    if (-not (Test-DockerRunning)) {
        return $false
    }
    
    if (-not (Test-Path "docker/docker-compose.yml")) {
        Write-ColorOutput "ERRORE: docker-compose.yml non trovato!" "Red"
        return $false
    }
    
    if (-not (Test-Path "data/Words.txt")) {
        Write-ColorOutput "ERRORE: File di input data/Words.txt non trovato!" "Red"
        return $false
    }
    
    Write-Host "Avviando il cluster..."
    docker-compose -f docker/docker-compose.yml up -d --build
    
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Cluster MapReduce avviato con successo!" "Green"
        Write-Host "Dashboard: http://localhost:8080"
        return $true
    } else {
        Write-ColorOutput "Errore durante l avvio del cluster" "Red"
        return $false
    }
}

function Stop-Cluster {
    Write-ColorOutput "=== FERMATA CLUSTER MAPREDUCE ===" "Yellow"
    Write-Host ""
    
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
    
    Write-Host ""
    Write-Host "Volumi:"
    docker volume ls | Where-Object { $_ -match "mapreduce" }
    
    Write-Host ""
    Write-Host "Rete:"
    docker network ls | Where-Object { $_ -match "mapreduce" }
}

function Show-Logs {
    Write-ColorOutput "=== LOG CLUSTER MAPREDUCE ===" "Blue"
    Write-Host ""
    Write-Host "Premi Ctrl+C per uscire dai log"
    Write-Host ""
    
    docker-compose -f docker/docker-compose.yml logs -f
}

function Test-ClusterHealth {
    Write-ColorOutput "=== HEALTH CHECK CLUSTER ===" "Cyan"
    Write-Host ""
    
    $containers = docker-compose -f docker/docker-compose.yml ps --services
    $runningContainers = docker-compose -f docker/docker-compose.yml ps --services --filter "status=running"
    
    if ($containers.Count -eq $runningContainers.Count) {
        Write-ColorOutput "Tutti i container sono in esecuzione" "Green"
    } else {
        Write-ColorOutput "Alcuni container non sono in esecuzione" "Red"
        docker-compose -f docker/docker-compose.yml ps
    }
    
    Write-Host "Verificando connettività di rete..."
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080" -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-ColorOutput "Dashboard accessibile su http://localhost:8080" "Green"
        }
    }
    catch {
        Write-ColorOutput "Dashboard non ancora accessibile" "Yellow"
    }
    
    $ports = @("8000", "8001", "8002")
    $leaderCount = 0
    
    foreach ($port in $ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                $leaderCount++
            }
        }
        catch {
            Write-Host "Master su porta $port non risponde"
        }
    }
    
    if ($leaderCount -gt 0) {
        Write-ColorOutput "Raft cluster operativo ($leaderCount master attivi)" "Green"
    } else {
        Write-ColorOutput "Raft cluster non operativo" "Red"
    }
}

function Test-FaultTolerance {
    Write-ColorOutput "=== TEST FAULT TOLERANCE ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Verifica stato iniziale..."
    Show-Status
    
    Write-Host ""
    Write-Host "2. Simulazione guasto master..."
    docker-compose -f docker/docker-compose.yml stop master1
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica elezione nuovo leader..."
    Test-ClusterHealth
    
    Write-Host ""
    Write-Host "4. Ripristino master..."
    docker-compose -f docker/docker-compose.yml start master1
    Start-Sleep -Seconds 10
    
    Write-Host "5. Verifica stato finale..."
    Test-ClusterHealth
    
    Write-ColorOutput "Test fault tolerance completato" "Green"
}

function Backup-Data {
    Write-ColorOutput "=== BACKUP DATI CLUSTER ===" "Yellow"
    Write-Host ""
    
    $backupDir = "backup-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    Write-Host "Creando backup in: $backupDir"
    
    docker run --rm -v mapreduce-project_raft-data:/data -v "${PWD}/$backupDir":/backup alpine tar czf /backup/raft-data.tar.gz -C /data .
    
    if (Test-Path "data/output") {
        Copy-Item -Path "data/output" -Destination "$backupDir/output" -Recurse
    }
    
    Write-ColorOutput "Backup completato in: $backupDir" "Green"
}

function Copy-OutputFiles {
    Write-ColorOutput "=== COPIA FILE DI OUTPUT DAL VOLUME DOCKER ===" "Blue"
    Write-Host ""
    
    if (-not (Test-DockerRunning)) {
        return $false
    }
    
    $activeWorker = $null
    $projectName = Split-Path (Get-Location) -Leaf
    if ($projectName -eq "") {
        $projectName = "mapreduce-project"
    }
    
    $workerContainers = docker-compose -f docker/docker-compose.yml ps --services | Where-Object { $_ -match "^worker\d+$" }
    
    foreach ($workerService in $workerContainers) {
        $containerName = "${projectName}-${workerService}-1"
        try {
            docker exec $containerName echo "test" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $activeWorker = $containerName
                break
            }
        }
        catch {
            $altContainerName = "${projectName}_${workerService}_1"
            try {
                docker exec $altContainerName echo "test" 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $activeWorker = $altContainerName
                    break
                }
            }
            catch {
                continue
            }
        }
    }
    
    if (-not $activeWorker) {
        Write-ColorOutput "ERRORE: Nessun container worker attivo trovato" "Red"
        Write-Host "Assicurati che i servizi MapReduce siano in esecuzione con: docker-compose up -d"
        Write-Host "Container disponibili:"
        docker-compose -f docker/docker-compose.yml ps
        return $false
    }
    
    Write-Host "Container worker attivo trovato: $activeWorker"
    Write-Host ""
    
    if (-not (Test-Path "data/output")) {
        New-Item -ItemType Directory -Path "data/output" -Force | Out-Null
        Write-Host "Cartella data/output creata"
    }
    
    Write-Host ""
    Write-Host "Ricerca e copia file di output..."
    $copiedFiles = 0
    $skippedFiles = 0
    
    for ($i = 0; $i -le 9; $i++) {
        $sourceFile = "/tmp/mapreduce/mr-out-$i"
        $destFile = "data/output/mr-out-$i"
        
        try {
            docker exec $activeWorker test -f $sourceFile | Out-Null
            if ($LASTEXITCODE -eq 0) {
                docker cp "$activeWorker`:$sourceFile" $destFile
                if ($LASTEXITCODE -eq 0) {
                    Write-ColorOutput "File copiato: mr-out-$i" "Green"
                    $copiedFiles++
                } else {
                    Write-ColorOutput "Errore copia file: mr-out-$i" "Red"
                }
            } else {
                $skippedFiles++
            }
        }
        catch {
            $skippedFiles++
        }
    }
    
    $unifiedSourceFile = "/tmp/mapreduce/final-output.txt"
    $unifiedDestFile = "data/output/final-output.txt"
    
    try {
        docker exec $activeWorker test -f $unifiedSourceFile | Out-Null
        if ($LASTEXITCODE -eq 0) {
            docker cp "$activeWorker`:$unifiedSourceFile" $unifiedDestFile
            if ($LASTEXITCODE -eq 0) {
                Write-ColorOutput "File finale unificato copiato: final-output.txt" "Green"
                $copiedFiles++
            } else {
                Write-ColorOutput "Errore copia file finale unificato" "Red"
            }
        } else {
            Write-Host "File finale unificato non trovato nel volume Docker"
        }
    }
    catch {
        Write-Host "File finale unificato non trovato nel volume Docker"
    }
    
    Write-Host ""
    if ($copiedFiles -gt 0) {
        Write-ColorOutput "Copiati $copiedFiles file di output in data/output/" "Green"
    } else {
        Write-ColorOutput "Nessun file di output trovato da copiare" "Yellow"
    }
    
    if ($skippedFiles -gt 0) {
        Write-Host "$skippedFiles file non trovati (normale se il job non e ancora completato)"
    }
    
    Write-Host ""
    Write-ColorOutput "=== COPIA COMPLETATA ===" "Green"
    
    if ($copiedFiles -gt 0) {
        Write-Host "File nella cartella data/output:"
        Get-ChildItem "data/output" | ForEach-Object {
            Write-Host "  File: $($_.Name) - Size: $($_.Length) bytes"
        }
    }
    
    return $true
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

function New-Images {
    Write-ColorOutput "=== COSTRUZIONE IMMAGINI DOCKER ===" "Yellow"
    Write-Host ""
    
    docker-compose -f docker/docker-compose.yml build --no-cache
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Immagini costruite con successo" "Green"
        return $true
    } else {
        Write-ColorOutput "Errore durante la costruzione delle immagini" "Red"
        return $false
    }
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

function Get-RunningServices {
    try {
        return @(docker-compose -f docker/docker-compose.yml ps --services --filter "status=running")
    }
    catch {
        return @()
    }
}

function Start-ServiceIfStopped {
    param(
        [string]$Service
    )
    $running = Get-RunningServices
    if ($running -contains $Service) {
        Write-ColorOutput "Servizio gia in esecuzione: $Service" "Yellow"
        return $false
    }
    Write-Host "Avvio servizio: $Service"
    docker-compose -f docker/docker-compose.yml up -d $Service
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Servizio avviato: $Service" "Green"
        return $true
    } else {
        Write-ColorOutput "Errore avvio servizio: $Service" "Red"
        return $false
    }
}

switch ($Action.ToLower()) {
    "start" {
        if ($Clean) {
            Clean-All
        }
        
        if ($Build -or $Clean) {
            if (-not (New-Images)) {
                exit 1
            }
        }
        
        if (Start-Cluster) {
            Write-Host ""
            Show-Status
            Write-Host ""
            Test-ClusterHealth
            
            if ($CopyOutput) {
                Write-Host ""
                Copy-OutputFiles
            }
            
            Write-Host ""
            Write-ColorOutput "=== CLUSTER MAPREDUCE PRONTO! ===" "Green"
            Write-Host ""
            Write-Host "Servizi disponibili:"
            Write-Host "  - Dashboard: http://localhost:8080"
            Write-Host "  - Metrics: http://localhost:9090"
            Write-Host "  - Master0 RPC: localhost:8000"
            Write-Host "  - Master1 RPC: localhost:8001"
            Write-Host "  - Master2 RPC: localhost:8002"
            Write-Host ""
        } else {
            Write-ColorOutput "Errore durante l'avvio del cluster" "Red"
            exit 1
        }
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
        Test-ClusterHealth
        if ($FaultTest) {
            Write-Host ""
            Test-FaultTolerance
        }
    }
    "clean" {
        Clean-All
    }
    "reset" {
        Write-ColorOutput "=== RESET CLUSTER ALLA CONFIGURAZIONE DI DEFAULT ===" "Yellow"
        Clean-All
        if (-not (Start-Cluster)) { exit 1 }
    }
    "dashboard" {
        Write-ColorOutput "=== APERTURA DASHBOARD ===" "Blue"
        Write-Host ""
        & "$PSScriptRoot/open-dashboard.ps1" -Quick
    }
    "backup" {
        Backup-Data
    }
    "copy-output" {
        if (Copy-OutputFiles) {
            Write-ColorOutput "Copia file di output completata con successo!" "Green"
        } else {
            Write-ColorOutput "Errore durante la copia dei file di output" "Red"
            exit 1
        }
    }
    "add-master" {
        Write-ColorOutput "=== AGGIUNTA MASTER ===" "Cyan"
        $candidates = @("master1", "master2")
        $started = $false
        foreach ($svc in $candidates) {
            if (Start-ServiceIfStopped -Service $svc) { $started = $true; break }
        }
        if (-not $started) { Write-ColorOutput "Nessun master aggiunto (tutti gia attivi)" "Yellow" }
    }
    "add-worker" {
        Write-ColorOutput "=== AGGIUNTA WORKER ===" "Cyan"
        # Cerca il prossimo servizio workerN disponibile definito nel compose
        $services = @(docker-compose -f docker/docker-compose.yml config --services 2>$null) | Where-Object { $_ -match '^worker\d+$' }
        if (-not $services -or $services.Count -eq 0) { $services = @("worker1","worker2","worker3") }
        $running = Get-RunningServices
        $next = $null
        foreach ($s in ($services | Sort-Object {[int]($_ -replace 'worker','')})) {
            if ($running -notcontains $s) { $next = $s; break }
        }
        if ($null -eq $next) {
            Write-ColorOutput "Nessun worker disponibile nel compose (tutti attivi)." "Yellow"
        } else {
            if (Start-ServiceIfStopped -Service $next) {
                Write-ColorOutput "Worker avviato: $next" "Green"
            } else {
                Write-ColorOutput "Errore avvio worker: $next" "Red"
            }
        }
    }
    default {
        Write-ColorOutput "Azione non riconosciuta: $Action" "Red"
        Show-Help
        exit 1
    }
}

Write-Host ""
Write-ColorOutput "=== Operazione completata ===" "Green"
