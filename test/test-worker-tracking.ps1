# Test specifico per la correzione del tracking dei worker
# Verifica che nella dashboard appaiano solo i worker effettivi

param(
    [switch]$Demo,
    [switch]$TestOnly
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

function Get-WorkerCount {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/workers" -UseBasicParsing
        $workers = $response.Content | ConvertFrom-Json
        return $workers.Count
    } catch {
        Write-ColorOutput "Errore nel recupero dei worker: $($_.Exception.Message)" $Red
        return -1
    }
}

function Wait-ForWorkers {
    param([int]$ExpectedCount, [int]$MaxWaitSeconds = 30)
    
    $startTime = Get-Date
    $actualCount = -1
    
    do {
        $actualCount = Get-WorkerCount
        if ($actualCount -eq $ExpectedCount) {
            Write-ColorOutput "✓ Trovati $actualCount worker (attesi: $ExpectedCount)" $Green
            return $true
        }
        
        if ($actualCount -gt 0) {
            Write-ColorOutput "Trovati $actualCount worker (attesi: $ExpectedCount), aspetto..." $Yellow
        }
        
        Start-Sleep -Seconds 2
        $elapsed = (Get-Date) - $startTime
    } while ($elapsed.TotalSeconds -lt $MaxWaitSeconds)
    
    Write-ColorOutput "✗ Timeout: trovati $actualCount worker invece di $ExpectedCount" $Red
    return $false
}

function Test-WorkerTracking {
    Write-ColorOutput "=== TEST CORREZIONE TRACKING WORKER ===" $Blue
    Write-Host ""
    
    # Verifica che Docker sia in esecuzione
    try {
        docker version | Out-Null
        Write-ColorOutput "✓ Docker è in esecuzione" $Green
    }
    catch {
        Write-ColorOutput "✗ Docker non è in esecuzione!" $Red
        return
    }
    
    # Verifica che il docker-compose.yml esista
    if (-not (Test-Path "docker-compose.yml")) {
        Write-ColorOutput "✗ docker-compose.yml non trovato!" $Red
        return
    }
    Write-ColorOutput "✓ docker-compose.yml trovato" $Green
    
    Write-Host ""
    Write-ColorOutput "=== FASE 1: AVVIO CLUSTER BASE ===" $Cyan
    
    # Avvia cluster con configurazione di default (3 master, 2 worker)
    Write-ColorOutput "Avvio cluster di base..." $Yellow
    & .\scripts\docker-manager.ps1 start
    Start-Sleep -Seconds 15
    
    # Verifica che la dashboard sia attiva
    Write-ColorOutput "Verifica dashboard..." $Yellow
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/health" -UseBasicParsing
        Write-ColorOutput "✓ Dashboard attiva" $Green
    } catch {
        Write-ColorOutput "✗ Dashboard non raggiungibile!" $Red
        return
    }
    
    # Verifica numero iniziale di worker
    Write-ColorOutput "Verifica numero iniziale di worker (attesi: 2)..." $Yellow
    if (-not (Wait-ForWorkers -ExpectedCount 2)) {
        Write-ColorOutput "✗ Test fallito: numero iniziale di worker errato" $Red
        return
    }
    
    Write-Host ""
    Write-ColorOutput "=== FASE 2: AGGIUNTA WORKER DINAMICO ===" $Cyan
    
    # Aggiunge un terzo worker
    Write-ColorOutput "Aggiunta worker con ID 3..." $Yellow
    & .\scripts\docker-manager.ps1 add-worker -NewWorkerID 3
    Start-Sleep -Seconds 10
    
    # Verifica che ora ci siano 3 worker
    Write-ColorOutput "Verifica numero di worker dopo aggiunta (attesi: 3)..." $Yellow
    if (-not (Wait-ForWorkers -ExpectedCount 3)) {
        Write-ColorOutput "✗ Test fallito: numero di worker dopo aggiunta errato" $Red
        return
    }
    
    Write-Host ""
    Write-ColorOutput "=== FASE 3: RIMOZIONE WORKER ===" $Cyan
    
    # Rimuove un worker (fermando il container)
    Write-ColorOutput "Rimozione worker 3..." $Yellow
    docker stop mapreduce-worker-3 2>$null
    docker rm mapreduce-worker-3 2>$null
    Start-Sleep -Seconds 10
    
    # Verifica che ora ci siano di nuovo 2 worker
    Write-ColorOutput "Verifica numero di worker dopo rimozione (attesi: 2)..." $Yellow
    if (-not (Wait-ForWorkers -ExpectedCount 2)) {
        Write-ColorOutput "✗ Test fallito: numero di worker dopo rimozione errato" $Red
        return
    }
    
    Write-Host ""
    Write-ColorOutput "=== FASE 4: TEST PERSISTENZA ===" $Cyan
    
    # Testa che i worker rimangano stabili per un po'
    Write-ColorOutput "Test stabilità per 30 secondi..." $Yellow
    $stableCount = 0
    for ($i = 1; $i -le 6; $i++) {
        $count = Get-WorkerCount
        if ($count -eq 2) {
            $stableCount++
            Write-ColorOutput "Check $i`: $count worker (stabile)" $Green
        } else {
            Write-ColorOutput "Check $i`: $count worker (instabile!)" $Red
        }
        Start-Sleep -Seconds 5
    }
    
    if ($stableCount -ge 5) {
        Write-ColorOutput "✓ Worker tracking stabile" $Green
    } else {
        Write-ColorOutput "✗ Worker tracking instabile" $Red
    }
    
    Write-Host ""
    Write-ColorOutput "=== RISULTATO FINALE ===" $Blue
    
    # Mostra stato finale
    $finalCount = Get-WorkerCount
    Write-ColorOutput "Worker finali: $finalCount" $Cyan
    
    if ($finalCount -eq 2) {
        Write-ColorOutput "✓ TEST COMPLETATO CON SUCCESSO!" $Green
        Write-ColorOutput "✓ La correzione del tracking dei worker funziona correttamente" $Green
        Write-ColorOutput "✓ I worker appaiono/scompaiono dinamicamente nella dashboard" $Green
    } else {
        Write-ColorOutput "✗ TEST FALLITO!" $Red
        Write-ColorOutput "✗ Il tracking dei worker non funziona correttamente" $Red
    }
    
    Write-Host ""
    Write-ColorOutput "Per verificare manualmente:" $Yellow
    Write-ColorOutput "Apri il browser su: http://localhost:8080" $Cyan
    Write-ColorOutput "Vai alla tabella Workers per vedere i worker in tempo reale" $Cyan
}

function Test-OnlyWorkerAPI {
    Write-ColorOutput "=== TEST SOLO API WORKER ===" $Blue
    Write-Host ""
    
    # Verifica che la dashboard sia attiva
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/health" -UseBasicParsing
        Write-ColorOutput "✓ Dashboard attiva" $Green
    } catch {
        Write-ColorOutput "✗ Dashboard non raggiungibile!" $Red
        return
    }
    
    # Test API worker
    Write-ColorOutput "Test API Workers..." $Yellow
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/workers" -UseBasicParsing
        $workers = $response.Content | ConvertFrom-Json
        Write-ColorOutput "✓ Workers API funzionante" $Green
        Write-ColorOutput "Trovati $($workers.Count) worker:" $Cyan
        
        foreach ($worker in $workers) {
            Write-ColorOutput "  - ID: $($worker.id), Status: $($worker.status), Tasks: $($worker.tasks_done)" $Cyan
        }
    } catch {
        Write-ColorOutput "✗ Workers API non funzionante: $($_.Exception.Message)" $Red
    }
}

# Main execution
if ($Demo) {
    Test-WorkerTracking
} elseif ($TestOnly) {
    Test-OnlyWorkerAPI
} else {
    Write-ColorOutput "=== TEST CORREZIONE TRACKING WORKER ===" $Blue
    Write-Host ""
    Write-Host "Usage: .\test\test-worker-tracking.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Demo     Esegue test completo del tracking dei worker"
    Write-Host "  -TestOnly Testa solo l'API dei worker (richiede dashboard attiva)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\test\test-worker-tracking.ps1 -Demo"
    Write-Host "  .\test\test-worker-tracking.ps1 -TestOnly"
    Write-Host ""
}

Write-Host ""
Write-ColorOutput "=== Script completato ===" $Green
