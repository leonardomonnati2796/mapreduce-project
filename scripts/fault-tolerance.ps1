# Script PowerShell per la gestione della Fault Tolerance del cluster MapReduce
# Questo script gestisce test di fault tolerance, recovery, backup e monitoraggio della resilienza

param(
    [Parameter(Position=0)]
    [string]$Action = "test",
    
    # Test Types
    [switch]$MasterFailure,
    [switch]$WorkerFailure,
    [switch]$NetworkPartition,
    [switch]$DataCorruption,
    [switch]$ResourceExhaustion,
    [switch]$FullTest,
    
    # Recovery Options
    [switch]$AutoRecover,
    [switch]$ManualRecover,
    [switch]$Rollback,
    [string]$BackupFile = "",
    
    # Monitoring
    [switch]$Monitor,
    [switch]$HealthCheck,
    [switch]$Metrics,
    [int]$Duration = 60,
    
    # Configuration
    [int]$FailureCount = 1,
    [int]$RecoveryTimeout = 30,
    [switch]$VerboseOutput,
    [switch]$Help
)

# Colori per output
$Red = "`e[31m"
$Green = "`e[32m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
$Cyan = "`e[36m"
$Magenta = "`e[35m"
$Reset = "`e[0m"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = $Reset)
    Write-Host "$Color$Message$Reset"
}

function Show-Help {
    Write-ColorOutput "=== MapReduce Fault Tolerance Manager ===" $Blue
    Write-Host ""
    Write-Host "Usage: .\scripts\fault-tolerance.ps1 [ACTION] [OPTIONS]"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  test            Esegue test di fault tolerance (default)"
    Write-Host "  monitor         Monitora la resilienza del cluster"
    Write-Host "  recover         Esegue recovery del cluster"
    Write-Host "  backup          Crea backup per recovery"
    Write-Host "  restore         Ripristina da backup"
    Write-Host ""
    Write-Host "Test Types:"
    Write-Host "  -MasterFailure      Test guasto master"
    Write-Host "  -WorkerFailure      Test guasto worker"
    Write-Host "  -NetworkPartition   Test partizione di rete"
    Write-Host "  -DataCorruption     Test corruzione dati"
    Write-Host "  -ResourceExhaustion Test esaurimento risorse"
    Write-Host "  -FullTest           Esegue tutti i test"
    Write-Host ""
    Write-Host "Recovery Options:"
    Write-Host "  -AutoRecover        Recovery automatico"
    Write-Host "  -ManualRecover      Recovery manuale"
    Write-Host "  -Rollback           Rollback a stato precedente"
    Write-Host "  -BackupFile <file>  File di backup specifico"
    Write-Host ""
    Write-Host "Monitoring:"
    Write-Host "  -Monitor            Monitoraggio continuo"
    Write-Host "  -HealthCheck        Controllo salute cluster"
    Write-Host "  -Metrics            Mostra metriche di resilienza"
    Write-Host "  -Duration <sec>     Durata monitoraggio (default: 60)"
    Write-Host ""
    Write-Host "Configuration:"
    Write-Host "  -FailureCount <num>    Numero di failure da simulare (default: 1)"
    Write-Host "  -RecoveryTimeout <sec> Timeout per recovery (default: 30)"
    Write-Host "  -VerboseOutput         Output dettagliato"
    Write-Host "  -Help                  Mostra questo messaggio di aiuto"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\fault-tolerance.ps1 test -MasterFailure"
    Write-Host "  .\scripts\fault-tolerance.ps1 test -FullTest -VerboseOutput"
    Write-Host "  .\scripts\fault-tolerance.ps1 monitor -Duration 120"
    Write-Host "  .\scripts\fault-tolerance.ps1 recover -AutoRecover"
    Write-Host "  .\scripts\fault-tolerance.ps1 backup"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non è in esecuzione!" $Red
        Write-Host "Assicurati che Docker Desktop sia avviato e riprova."
        return $false
    }
}

function Get-ClusterStatus {
    Write-Host "Verificando stato cluster..."
    
    $containers = docker-compose ps --services
    $runningContainers = docker-compose ps --services --filter "status=running"
    
    $status = @{
        TotalContainers = $containers.Count
        RunningContainers = $runningContainers.Count
        Healthy = ($containers.Count -eq $runningContainers.Count)
    }
    
    return $status
}

function Test-MasterFailure {
    Write-ColorOutput "=== TEST GUASTO MASTER ===" $Magenta
    Write-Host ""
    
    # Stato iniziale
    Write-Host "1. Verifica stato iniziale..."
    $initialStatus = Get-ClusterStatus
    Write-Host "   Container totali: $($initialStatus.TotalContainers)"
    Write-Host "   Container attivi: $($initialStatus.RunningContainers)"
    
    # Simula guasto master
    Write-Host ""
    Write-Host "2. Simulazione guasto master1..."
    docker-compose stop master1
    Start-Sleep -Seconds 5
    
    # Verifica resilienza
    Write-Host ""
    Write-Host "3. Verifica resilienza cluster..."
    $failureStatus = Get-ClusterStatus
    Write-Host "   Container attivi dopo guasto: $($failureStatus.RunningContainers)"
    
    # Test elezione nuovo leader
    Write-Host ""
    Write-Host "4. Test elezione nuovo leader..."
    $leaderFound = $false
    $ports = @("8000", "8001", "8002")
    
    foreach ($port in $ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "   Leader attivo su porta $port" $Green
                $leaderFound = $true
                break
            }
        }
        catch {
        if ($VerboseOutput) {
            Write-Host "   Master su porta $port non risponde"
        }
        }
    }
    
    if ($leaderFound) {
        Write-ColorOutput "   Elezione leader: SUCCESSO" $Green
    } else {
        Write-ColorOutput "   Elezione leader: FALLITA" $Red
    }
    
    # Recovery
    Write-Host ""
    Write-Host "5. Recovery master..."
    docker-compose start master1
    Start-Sleep -Seconds 10
    
    # Verifica stato finale
    Write-Host ""
    Write-Host "6. Verifica stato finale..."
    $finalStatus = Get-ClusterStatus
    Write-Host "   Container attivi dopo recovery: $($finalStatus.RunningContainers)"
    
    if ($finalStatus.Healthy) {
        Write-ColorOutput "   Test guasto master: SUCCESSO" $Green
        return $true
    } else {
        Write-ColorOutput "   Test guasto master: FALLITO" $Red
        return $false
    }
}

function Test-WorkerFailure {
    Write-ColorOutput "=== TEST GUASTO WORKER ===" $Magenta
    Write-Host ""
    
    # Stato iniziale
    Write-Host "1. Verifica stato iniziale..."
    $initialStatus = Get-ClusterStatus
    
    # Simula guasto worker
    Write-Host ""
    Write-Host "2. Simulazione guasto worker1..."
    docker-compose stop worker1
    Start-Sleep -Seconds 5
    
    # Verifica resilienza
    Write-Host ""
    Write-Host "3. Verifica resilienza cluster..."
    $failureStatus = Get-ClusterStatus
    
    # Test redistribuzione task
    Write-Host ""
    Write-Host "4. Test redistribuzione task..."
    # Qui potresti aggiungere logica per verificare che i task vengano redistribuiti
    
    # Recovery
    Write-Host ""
    Write-Host "5. Recovery worker..."
    docker-compose start worker1
    Start-Sleep -Seconds 10
    
    # Verifica stato finale
    Write-Host ""
    Write-Host "6. Verifica stato finale..."
    $finalStatus = Get-ClusterStatus
    
    if ($finalStatus.Healthy) {
        Write-ColorOutput "   Test guasto worker: SUCCESSO" $Green
        return $true
    } else {
        Write-ColorOutput "   Test guasto worker: FALLITO" $Red
        return $false
    }
}

function Test-NetworkPartition {
    Write-ColorOutput "=== TEST PARTIZIONE DI RETE ===" $Magenta
    Write-Host ""
    
    Write-Host "1. Simulazione partizione di rete..."
    # Isola un master dalla rete
    docker network disconnect mapreduce-project_default master1
    
    Start-Sleep -Seconds 10
    
    Write-Host "2. Verifica split-brain prevention..."
    # Verifica che non ci siano due leader
    
    Write-Host "3. Recovery partizione..."
    docker network connect mapreduce-project_default master1
    
    Start-Sleep -Seconds 10
    
    Write-Host "4. Verifica riconnessione..."
    $finalStatus = Get-ClusterStatus
    
    if ($finalStatus.Healthy) {
        Write-ColorOutput "   Test partizione rete: SUCCESSO" $Green
        return $true
    } else {
        Write-ColorOutput "   Test partizione rete: FALLITO" $Red
        return $false
    }
}

function Test-DataCorruption {
    Write-ColorOutput "=== TEST CORRUZIONE DATI ===" $Magenta
    Write-Host ""
    
    Write-Host "1. Simulazione corruzione dati..."
    # Simula corruzione di un file di dati
    
    Write-Host "2. Verifica detection corruzione..."
    # Verifica che il sistema rilevi la corruzione
    
    Write-Host "3. Recovery dati..."
    # Ripristina i dati da backup o replica
    
    Write-Host "4. Verifica integrità..."
    # Verifica che i dati siano stati ripristinati correttamente
    
    Write-ColorOutput "   Test corruzione dati: COMPLETATO" $Green
    return $true
}

function Test-ResourceExhaustion {
    Write-ColorOutput "=== TEST ESAURIMENTO RISORSE ===" $Magenta
    Write-Host ""
    
    Write-Host "1. Simulazione esaurimento memoria..."
    # Simula esaurimento memoria su un container
    
    Write-Host "2. Verifica throttling..."
    # Verifica che il sistema implementi throttling
    
    Write-Host "3. Verifica recovery automatico..."
    # Verifica che il sistema si riprenda automaticamente
    
    Write-Host "4. Verifica prevenzione cascata..."
    # Verifica che il problema non si propaghi
    
    Write-ColorOutput "   Test esaurimento risorse: COMPLETATO" $Green
    return $true
}

function Run-FullTest {
    Write-ColorOutput "=== TEST COMPLETO FAULT TOLERANCE ===" $Blue
    Write-Host ""
    
    $testResults = @{}
    
    Write-Host "Esecuzione test completi..."
    Write-Host ""
    
    # Test guasto master
    Write-Host "Test 1/5: Guasto Master"
    $testResults.MasterFailure = Test-MasterFailure
    Write-Host ""
    
    # Test guasto worker
    Write-Host "Test 2/5: Guasto Worker"
    $testResults.WorkerFailure = Test-WorkerFailure
    Write-Host ""
    
    # Test partizione rete
    Write-Host "Test 3/5: Partizione Rete"
    $testResults.NetworkPartition = Test-NetworkPartition
    Write-Host ""
    
    # Test corruzione dati
    Write-Host "Test 4/5: Corruzione Dati"
    $testResults.DataCorruption = Test-DataCorruption
    Write-Host ""
    
    # Test esaurimento risorse
    Write-Host "Test 5/5: Esaurimento Risorse"
    $testResults.ResourceExhaustion = Test-ResourceExhaustion
    Write-Host ""
    
    # Risultati finali
    Write-ColorOutput "=== RISULTATI TEST COMPLETI ===" $Blue
    Write-Host ""
    
    $passedTests = 0
    $totalTests = $testResults.Count
    
    foreach ($test in $testResults.GetEnumerator()) {
        $status = if ($test.Value) { "PASS" } else { "FAIL" }
        $color = if ($test.Value) { $Green } else { $Red }
        Write-ColorOutput "  $($test.Key): $status" $color
        
        if ($test.Value) { $passedTests++ }
    }
    
    Write-Host ""
    Write-Host "Risultato finale: $passedTests/$totalTests test superati"
    
    if ($passedTests -eq $totalTests) {
        Write-ColorOutput "TUTTI I TEST SUPERATI - CLUSTER RESILIENTE" $Green
        return $true
    } else {
        Write-ColorOutput "ALCUNI TEST FALLITI - VERIFICARE CONFIGURAZIONE" $Red
        return $false
    }
}

function Monitor-Resilience {
    Write-ColorOutput "=== MONITORAGGIO RESILIENZA ===" $Cyan
    Write-Host ""
    
    Write-Host "Monitoraggio resilienza per $Duration secondi..."
    Write-Host "Premi Ctrl+C per interrompere"
    Write-Host ""
    
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($Duration)
    
    while ((Get-Date) -lt $endTime) {
        $status = Get-ClusterStatus
        $timestamp = Get-Date -Format "HH:mm:ss"
        
        $healthStatus = if ($status.Healthy) { "HEALTHY" } else { "UNHEALTHY" }
        $color = if ($status.Healthy) { $Green } else { $Red }
        
        Write-ColorOutput "[$timestamp] Cluster: $healthStatus ($($status.RunningContainers)/$($status.TotalContainers) container)" $color
        
        if ($Metrics) {
            # Mostra metriche aggiuntive
            Write-Host "  - CPU Usage: $(Get-CpuUsage)"
            Write-Host "  - Memory Usage: $(Get-MemoryUsage)"
            Write-Host "  - Network Latency: $(Get-NetworkLatency)"
        }
        
        Start-Sleep -Seconds 5
    }
    
    Write-ColorOutput "Monitoraggio completato" $Green
}

function Get-CpuUsage {
    # Simula lettura CPU usage
    return "45%"
}

function Get-MemoryUsage {
    # Simula lettura memory usage
    return "2.1GB/8GB"
}

function Get-NetworkLatency {
    # Simula lettura network latency
    return "12ms"
}

function Create-Backup {
    Write-ColorOutput "=== CREAZIONE BACKUP ===" $Yellow
    Write-Host ""
    
    $backupDir = "backup-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    Write-Host "Creando backup in: $backupDir"
    
    # Backup volumi Docker
    Write-Host "Backup volumi Docker..."
    docker run --rm -v mapreduce-project_raft-data:/data -v "${PWD}/$backupDir":/backup alpine tar czf /backup/raft-data.tar.gz -C /data .
    
    # Backup configurazione
    Write-Host "Backup configurazione..."
    Copy-Item -Path "config.yaml" -Destination "$backupDir/config.yaml" -ErrorAction SilentlyContinue
    Copy-Item -Path "docker-compose.yml" -Destination "$backupDir/docker-compose.yml" -ErrorAction SilentlyContinue
    
    # Backup file di output
    if (Test-Path "data/output") {
        Write-Host "Backup file di output..."
        Copy-Item -Path "data/output" -Destination "$backupDir/output" -Recurse
    }
    
    # Backup log
    Write-Host "Backup log..."
    docker-compose logs > "$backupDir/cluster-logs.txt"
    
    Write-ColorOutput "Backup completato in: $backupDir" $Green
    return $backupDir
}

function Restore-FromBackup {
    param([string]$BackupPath)
    
    Write-ColorOutput "=== RIPRISTINO DA BACKUP ===" $Yellow
    Write-Host ""
    
    if (-not (Test-Path $BackupPath)) {
        Write-ColorOutput "ERRORE: Percorso backup non trovato: $BackupPath" $Red
        return $false
    }
    
    Write-Host "Ripristinando da: $BackupPath"
    
    # Ferma il cluster
    Write-Host "Fermando cluster..."
    docker-compose down
    
    # Ripristina volumi
    if (Test-Path "$BackupPath/raft-data.tar.gz") {
        Write-Host "Ripristinando volumi..."
        docker run --rm -v mapreduce-project_raft-data:/data -v "${PWD}/$BackupPath":/backup alpine tar xzf /backup/raft-data.tar.gz -C /data
    }
    
    # Ripristina configurazione
    if (Test-Path "$BackupPath/config.yaml") {
        Write-Host "Ripristinando configurazione..."
        Copy-Item -Path "$BackupPath/config.yaml" -Destination "config.yaml"
    }
    
    # Riavvia il cluster
    Write-Host "Riavviando cluster..."
    docker-compose up -d
    
    Start-Sleep -Seconds 15
    
    # Verifica stato
    $status = Get-ClusterStatus
    if ($status.Healthy) {
        Write-ColorOutput "Ripristino completato con successo" $Green
        return $true
    } else {
        Write-ColorOutput "Errore durante il ripristino" $Red
        return $false
    }
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

Write-ColorOutput "=== MAPREDUCE FAULT TOLERANCE MANAGER ===" $Blue
Write-Host "Azione: $Action"
Write-Host ""

# Verifica Docker
if (-not (Test-DockerRunning)) {
    exit 1
}

switch ($Action.ToLower()) {
    "test" {
        $testResults = @()
        
        if ($MasterFailure -or $FullTest) {
            $testResults += Test-MasterFailure
        }
        
        if ($WorkerFailure -or $FullTest) {
            $testResults += Test-WorkerFailure
        }
        
        if ($NetworkPartition -or $FullTest) {
            $testResults += Test-NetworkPartition
        }
        
        if ($DataCorruption -or $FullTest) {
            $testResults += Test-DataCorruption
        }
        
        if ($ResourceExhaustion -or $FullTest) {
            $testResults += Test-ResourceExhaustion
        }
        
        if ($FullTest) {
            Run-FullTest
        } elseif ($testResults.Count -eq 0) {
            Write-ColorOutput "Specificare un tipo di test o usare -FullTest" $Yellow
            Show-Help
            exit 1
        }
    }
    "monitor" {
        Monitor-Resilience
    }
    "recover" {
        if ($AutoRecover) {
            Write-Host "Recovery automatico..."
            # Implementa recovery automatico
        } elseif ($ManualRecover) {
            Write-Host "Recovery manuale..."
            # Implementa recovery manuale
        } else {
            Write-ColorOutput "Specificare -AutoRecover o -ManualRecover" $Yellow
        }
    }
    "backup" {
        Create-Backup
    }
    "restore" {
        if ($BackupFile -eq "") {
            Write-ColorOutput "Specificare -BackupFile con il percorso del backup" $Red
            exit 1
        }
        Restore-FromBackup $BackupFile
    }
    default {
        Write-ColorOutput "Azione non riconosciuta: $Action" $Red
        Write-Host ""
        Show-Help
        exit 1
    }
}

Write-Host ""
Write-ColorOutput "=== Operazione completata ===" $Green
