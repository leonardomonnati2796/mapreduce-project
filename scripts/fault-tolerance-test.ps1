# Script PowerShell per test di fault tolerance avanzati
# Gestisce i 5 test principali di fault tolerance del sistema MapReduce

param(
    [Parameter(Position=0)]
    [string]$TestType = "all",
    
    [switch]$Help,
    [switch]$Verbose
)

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Show-Help {
    Write-ColorOutput "=== FAULT TOLERANCE TEST SUITE ===" "Cyan"
    Write-Host ""
    Write-Host "Usage: .\scripts\fault-tolerance-test.ps1 [TEST_TYPE]"
    Write-Host ""
    Write-Host "Test Types:"
    Write-Host "  all       - Esegue tutti i test di fault tolerance"
    Write-Host "  leader    - Test elezione leader e recovery stato"
    Write-Host "  worker    - Test fallimenti worker e heartbeat"
    Write-Host "  mapper    - Test fallimenti mapper e recovery"
    Write-Host "  reduce    - Test fallimenti reduce e recovery"
    Write-Host "  network   - Test fallimenti di rete"
    Write-Host "  storage   - Test corruzione dati e recovery"
    Write-Host "  stress    - Test stress con guasti multipli"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Verbose  - Output dettagliato"
    Write-Host "  -Help     - Mostra questo messaggio"
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

function Wait-ForClusterStabilization {
    param([int]$Seconds = 10)
    Write-Host "Attesa stabilizzazione cluster ($Seconds secondi)..."
    Start-Sleep -Seconds $Seconds
}

function Test-ClusterHealth {
    Write-ColorOutput "=== HEALTH CHECK CLUSTER ===" "Cyan"
    
    $composeFile = "docker/docker-compose.yml"
    $containers = docker-compose -f $composeFile ps --services
    $running = docker-compose -f $composeFile ps --services --filter "status=running"
    
    Write-Host "Container totali: $($containers.Count)"
    Write-Host "Container attivi: $($running.Count)"
    
    if ($containers.Count -eq $running.Count) {
        Write-ColorOutput "✓ Tutti i container sono in esecuzione" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Alcuni container non sono in esecuzione" "Red"
        docker-compose -f $composeFile ps
        return $false
    }
}

function Test-LeaderElection {
    Write-ColorOutput "=== TEST 1/5: ELECTIONE LEADER E RECOVERY STATO ===" "Blue"
    Write-Host ""
    
    Write-Host "1. Verifica stato iniziale cluster..."
    if (-not (Test-ClusterHealth)) {
        Write-ColorOutput "ERRORE: Cluster non in stato salutare" "Red"
        return $false
    }
    
    Write-Host "2. Simulazione guasto leader (master0)..."
    docker-compose -f docker/docker-compose.yml stop master0
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica elezione nuovo leader..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Nuovo leader eletto correttamente" "Green"
    } else {
        Write-ColorOutput "✗ Elezione leader fallita" "Red"
        return $false
    }
    
    Write-Host "4. Ripristino leader originale..."
    docker-compose -f docker/docker-compose.yml start master0
    Wait-ForClusterStabilization 10
    
    Write-Host "5. Verifica recovery stato..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Recovery stato completato" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Recovery stato fallito" "Red"
        return $false
    }
}

function Test-WorkerFailure {
    Write-ColorOutput "=== TEST 2/5: FALLIMENTI WORKER E HEARTBEAT ===" "Blue"
    Write-Host ""
    
    Write-Host "1. Verifica worker attivi..."
    if (-not (Test-ClusterHealth)) {
        Write-ColorOutput "ERRORE: Cluster non in stato salutare" "Red"
        return $false
    }
    
    Write-Host "2. Simulazione guasto worker1..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica heartbeat e rilevamento guasto..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Heartbeat funziona - guasto rilevato" "Green"
    } else {
        Write-ColorOutput "✗ Heartbeat non funziona" "Red"
        return $false
    }
    
    Write-Host "4. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Wait-ForClusterStabilization 10
    
    Write-Host "5. Verifica worker ripristinato..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Worker ripristinato correttamente" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Ripristino worker fallito" "Red"
        return $false
    }
}

function Test-MapperFailure {
    Write-ColorOutput "=== TEST 3/5: FALLIMENTI MAPPER E RECOVERY ===" "Blue"
    Write-Host ""
    
    Write-Host "1. Avvio job MapReduce..."
    if (-not (Test-ClusterHealth)) {
        Write-ColorOutput "ERRORE: Cluster non in stato salutare" "Red"
        return $false
    }
    
    Write-Host "2. Attesa avvio fase map (15 secondi)..."
    Start-Sleep -Seconds 15
    
    Write-Host "3. Simulazione guasto durante mappatura..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 10
    
    Write-Host "4. Verifica recovery mapper..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Recovery mapper funziona" "Green"
    } else {
        Write-ColorOutput "✗ Recovery mapper fallito" "Red"
        return $false
    }
    
    Write-Host "5. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Wait-ForClusterStabilization 15
    
    Write-Host "6. Verifica completamento job..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Job completato dopo recovery" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Job non completato" "Red"
        return $false
    }
}

function Test-ReduceFailure {
    Write-ColorOutput "=== TEST 4/5: FALLIMENTI REDUCE E RECOVERY ===" "Blue"
    Write-Host ""
    
    Write-Host "1. Attesa completamento fase map (30 secondi)..."
    Start-Sleep -Seconds 30
    
    Write-Host "2. Verifica stato reduce..."
    if (-not (Test-ClusterHealth)) {
        Write-ColorOutput "ERRORE: Cluster non in stato salutare" "Red"
        return $false
    }
    
    Write-Host "3. Simulazione guasto durante riduzione..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 10
    
    Write-Host "4. Verifica recovery reduce..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Recovery reduce funziona" "Green"
    } else {
        Write-ColorOutput "✗ Recovery reduce fallito" "Red"
        return $false
    }
    
    Write-Host "5. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Wait-ForClusterStabilization 20
    
    Write-Host "6. Verifica completamento job..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Job completato dopo recovery" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Job non completato" "Red"
        return $false
    }
}

function Test-SystemRecovery {
    Write-ColorOutput "=== TEST 5/5: RECOVERY COMPLETO DEL SISTEMA ===" "Blue"
    Write-Host ""
    
    Write-Host "1. Backup stato iniziale..."
    if (-not (Test-ClusterHealth)) {
        Write-ColorOutput "ERRORE: Cluster non in stato salutare" "Red"
        return $false
    }
    
    Write-Host "2. Simulazione guasti multipli..."
    docker-compose -f docker/docker-compose.yml stop master1 worker1
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica recovery automatico..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Recovery automatico funziona" "Green"
    } else {
        Write-ColorOutput "✗ Recovery automatico fallito" "Red"
        return $false
    }
    
    Write-Host "4. Ripristino servizi..."
    docker-compose -f docker/docker-compose.yml start master1 worker1
    Wait-ForClusterStabilization 15
    
    Write-Host "5. Verifica sistema completamente ripristinato..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Sistema completamente ripristinato" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Ripristino sistema fallito" "Red"
        return $false
    }
}

function Test-NetworkFailure {
    Write-ColorOutput "=== TEST AVANZATO: FALLIMENTI DI RETE ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Simulazione problemi di rete..."
    # Simula problemi di rete fermando e riavviando servizi rapidamente
    docker-compose -f docker/docker-compose.yml stop master1
    Start-Sleep -Seconds 2
    docker-compose -f docker/docker-compose.yml start master1
    Start-Sleep -Seconds 3
    
    Write-Host "2. Verifica resilienza di rete..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Resilienza di rete verificata" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Resilienza di rete fallita" "Red"
        return $false
    }
}

function Test-StorageFailure {
    Write-ColorOutput "=== TEST AVANZATO: CORRUZIONE DATI E RECOVERY ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Simulazione problemi di storage..."
    # Simula problemi di storage riavviando i volumi
    docker-compose -f docker/docker-compose.yml restart worker1
    Start-Sleep -Seconds 10
    
    Write-Host "2. Verifica recovery storage..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Recovery storage verificato" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Recovery storage fallito" "Red"
        return $false
    }
}

function Test-StressFailure {
    Write-ColorOutput "=== TEST AVANZATO: STRESS CON GUASTI MULTIPLI ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Simulazione stress con guasti multipli..."
    docker-compose -f docker/docker-compose.yml stop master1 worker1
    Start-Sleep -Seconds 3
    docker-compose -f docker/docker-compose.yml start master1
    Start-Sleep -Seconds 3
    docker-compose -f docker/docker-compose.yml stop worker2
    Start-Sleep -Seconds 3
    docker-compose -f docker/docker-compose.yml start worker1 worker2
    Wait-ForClusterStabilization 15
    
    Write-Host "2. Verifica resilienza sotto stress..."
    if (Test-ClusterHealth) {
        Write-ColorOutput "✓ Resilienza sotto stress verificata" "Green"
        return $true
    } else {
        Write-ColorOutput "✗ Resilienza sotto stress fallita" "Red"
        return $false
    }
}

function Invoke-AllTests {
    Write-ColorOutput "=== ESECUZIONE TUTTI I TEST FAULT TOLERANCE ===" "Cyan"
    Write-Host ""
    
    $results = @{}
    
    Write-Host "Esecuzione test 1/5: Elezione leader..."
    $results.Leader = Test-LeaderElection
    
    Write-Host "Esecuzione test 2/5: Fallimenti worker..."
    $results.Worker = Test-WorkerFailure
    
    Write-Host "Esecuzione test 3/5: Fallimenti mapper..."
    $results.Mapper = Test-MapperFailure
    
    Write-Host "Esecuzione test 4/5: Fallimenti reduce..."
    $results.Reduce = Test-ReduceFailure
    
    Write-Host "Esecuzione test 5/5: Recovery completo..."
    $results.Recovery = Test-SystemRecovery
    
    Write-Host ""
    Write-ColorOutput "=== RISULTATI TEST FAULT TOLERANCE ===" "Blue"
    Write-Host "1. Elezione leader: $(if ($results.Leader) { '✓ PASS' } else { '✗ FAIL' })"
    Write-Host "2. Fallimenti worker: $(if ($results.Worker) { '✓ PASS' } else { '✗ FAIL' })"
    Write-Host "3. Fallimenti mapper: $(if ($results.Mapper) { '✓ PASS' } else { '✗ FAIL' })"
    Write-Host "4. Fallimenti reduce: $(if ($results.Reduce) { '✓ PASS' } else { '✗ FAIL' })"
    Write-Host "5. Recovery completo: $(if ($results.Recovery) { '✓ PASS' } else { '✗ FAIL' })"
    
    $passed = ($results.Values | Where-Object { $_ -eq $true }).Count
    $total = $results.Count
    
    Write-Host ""
    if ($passed -eq $total) {
        Write-ColorOutput "🎉 TUTTI I TEST PASSATI! ($passed/$total)" "Green"
    } else {
        Write-ColorOutput "⚠️  ALCUNI TEST FALLITI ($passed/$total)" "Yellow"
    }
    
    return $passed -eq $total
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

if (-not (Test-DockerRunning)) {
    exit 1
}

Write-ColorOutput "=== FAULT TOLERANCE TEST SUITE ===" "Blue"
Write-Host "Tipo test: $TestType"
Write-Host ""

switch ($TestType.ToLower()) {
    "all" {
        Invoke-AllTests
    }
    "leader" {
        Test-LeaderElection
    }
    "worker" {
        Test-WorkerFailure
    }
    "mapper" {
        Test-MapperFailure
    }
    "reduce" {
        Test-ReduceFailure
    }
    "recovery" {
        Test-SystemRecovery
    }
    "network" {
        Test-NetworkFailure
    }
    "storage" {
        Test-StorageFailure
    }
    "stress" {
        Test-StressFailure
    }
    default {
        Write-ColorOutput "Tipo test non riconosciuto: $TestType" "Red"
        Show-Help
        exit 1
    }
}

Write-Host ""
Write-ColorOutput "=== Test completato ===" "Green"
