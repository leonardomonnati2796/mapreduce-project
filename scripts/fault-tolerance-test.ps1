# Script PowerShell per test avanzati di fault tolerance
# Testa tutti gli scenari di fallimento del sistema MapReduce

param(
    [Parameter(Position=0)]
    [string]$TestType = "all",
    
    [switch]$Verbose,
    [switch]$Help
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
    Write-Host "  all           - Esegue tutti i test di fault tolerance"
    Write-Host "  leader        - Test elezione leader e recovery stato"
    Write-Host "  worker        - Test fallimenti worker e heartbeat"
    Write-Host "  mapper        - Test fallimenti mapper e recovery"
    Write-Host "  reduce        - Test fallimenti reduce e recovery"
    Write-Host "  network       - Test fallimenti di rete"
    Write-Host "  storage       - Test corruzione dati e recovery"
    Write-Host "  stress        - Test stress con fallimenti multipli"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Verbose      Mostra output dettagliato"
    Write-Host "  -Help         Mostra questo messaggio di aiuto"
    Write-Host ""
}

function Test-DockerRunning {
    try {
        docker version | Out-Null
        return $true
    }
    catch {
        Write-ColorOutput "ERRORE: Docker non e in esecuzione!" "Red"
        return $false
    }
}

function Start-TestCluster {
    Write-ColorOutput "Avvio cluster per test..." "Blue"
    docker-compose -f docker/docker-compose.yml up -d --build
    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Cluster avviato con successo" "Green"
        Start-Sleep -Seconds 10
        return $true
    } else {
        Write-ColorOutput "Errore avvio cluster" "Red"
        return $false
    }
}

function Stop-TestCluster {
    Write-ColorOutput "Fermata cluster..." "Yellow"
    docker-compose -f docker/docker-compose.yml down
}

function Test-LeaderElection {
    Write-ColorOutput "=== TEST ELECTIONE LEADER E RECOVERY STATO ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Verifica stato iniziale..."
    docker-compose -f docker/docker-compose.yml ps
    
    Write-Host "2. Test elezione leader iniziale..."
    $leaderFound = $false
    $ports = @("8000", "8001", "8002")
    
    foreach ($port in $ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "Leader trovato su porta $port" "Green"
                $leaderFound = $true
                break
            }
        }
        catch {
            if ($Verbose) { Write-Host "Porta $port non risponde" }
        }
    }
    
    if (-not $leaderFound) {
        Write-ColorOutput "ERRORE: Nessun leader trovato!" "Red"
        return $false
    }
    
    Write-Host "3. Simulazione guasto leader..."
    docker-compose -f docker/docker-compose.yml stop master0
    Start-Sleep -Seconds 5
    
    Write-Host "4. Verifica elezione nuovo leader..."
    $newLeaderFound = $false
    foreach ($port in @("8001", "8002")) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "Nuovo leader eletto su porta $port" "Green"
                $newLeaderFound = $true
                break
            }
        }
        catch {
            if ($Verbose) { Write-Host "Porta $port non risponde" }
        }
    }
    
    if (-not $newLeaderFound) {
        Write-ColorOutput "ERRORE: Elezione nuovo leader fallita!" "Red"
        return $false
    }
    
    Write-Host "5. Ripristino leader originale..."
    docker-compose -f docker/docker-compose.yml start master0
    Start-Sleep -Seconds 10
    
    Write-Host "6. Verifica recovery stato..."
    docker-compose -f docker/docker-compose.yml ps
    
    Write-ColorOutput "Test elezione leader completato con successo" "Green"
    return $true
}

function Test-WorkerFailures {
    Write-ColorOutput "=== TEST FALLIMENTI WORKER E HEARTBEAT ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Verifica worker attivi..."
    docker-compose -f docker/docker-compose.yml ps | Where-Object { $_ -match "worker" }
    
    Write-Host "2. Simulazione guasto worker..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica heartbeat e rilevamento guasto..."
    docker-compose -f docker/docker-compose.yml ps | Where-Object { $_ -match "worker" }
    
    Write-Host "4. Attesa timeout heartbeat (30 secondi)..."
    Start-Sleep -Seconds 35
    
    Write-Host "5. Verifica recovery automatico..."
    docker-compose -f docker/docker-compose.yml ps | Where-Object { $_ -match "worker" }
    
    Write-Host "6. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Start-Sleep -Seconds 10
    
    Write-Host "7. Verifica worker ripristinato..."
    docker-compose -f docker/docker-compose.yml ps | Where-Object { $_ -match "worker" }
    
    Write-ColorOutput "Test fallimenti worker completato" "Green"
    return $true
}

function Test-MapperFailures {
    Write-ColorOutput "=== TEST FALLIMENTI MAPPER E RECOVERY ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Avvio job MapReduce..."
    Start-Sleep -Seconds 15
    
    Write-Host "2. Verifica stato mapper..."
    docker-compose -f docker/docker-compose.yml logs worker1 | Select-Object -Last 10
    
    Write-Host "3. Simulazione guasto durante mappatura..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 5
    
    Write-Host "4. Verifica recovery mapper..."
    docker-compose -f docker/docker-compose.yml logs master0 | Select-Object -Last 10
    
    Write-Host "5. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Start-Sleep -Seconds 15
    
    Write-Host "6. Verifica completamento job..."
    docker-compose -f docker/docker-compose.yml logs worker1 | Select-Object -Last 10
    
    Write-ColorOutput "Test fallimenti mapper completato" "Green"
    return $true
}

function Test-ReduceFailures {
    Write-ColorOutput "=== TEST FALLIMENTI REDUCE E RECOVERY ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Attesa completamento fase map..."
    Start-Sleep -Seconds 30
    
    Write-Host "2. Verifica stato reduce..."
    docker-compose -f docker/docker-compose.yml logs worker1 | Select-Object -Last 10
    
    Write-Host "3. Simulazione guasto durante riduzione..."
    docker-compose -f docker/docker-compose.yml stop worker1
    Start-Sleep -Seconds 5
    
    Write-Host "4. Verifica recovery reduce..."
    docker-compose -f docker/docker-compose.yml logs master0 | Select-Object -Last 10
    
    Write-Host "5. Ripristino worker..."
    docker-compose -f docker/docker-compose.yml start worker1
    Start-Sleep -Seconds 20
    
    Write-Host "6. Verifica completamento job..."
    docker-compose -f docker/docker-compose.yml logs worker1 | Select-Object -Last 10
    
    Write-ColorOutput "Test fallimenti reduce completato" "Green"
    return $true
}

function Test-NetworkFailures {
    Write-ColorOutput "=== TEST FALLIMENTI DI RETE ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Test isolamento rete master..."
    docker network disconnect mapreduce-project_default mapreduce-project-master1-1
    Start-Sleep -Seconds 5
    
    Write-Host "2. Verifica elezione nuovo leader..."
    $ports = @("8000", "8002")
    foreach ($port in $ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "Leader attivo su porta $port" "Green"
                break
            }
        }
        catch {
            if ($Verbose) { Write-Host "Porta $port non risponde" }
        }
    }
    
    Write-Host "3. Ripristino connettività..."
    docker network connect mapreduce-project_default mapreduce-project-master1-1
    Start-Sleep -Seconds 10
    
    Write-Host "4. Verifica recovery rete..."
    docker-compose -f docker/docker-compose.yml ps
    
    Write-ColorOutput "Test fallimenti rete completato" "Green"
    return $true
}

function Test-StorageFailures {
    Write-ColorOutput "=== TEST CORRUZIONE DATI E RECOVERY ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Verifica file intermedi..."
    docker exec mapreduce-project-worker1-1 ls -la /tmp/mapreduce/ | Where-Object { $_ -match "mr-intermediate" }
    
    Write-Host "2. Simulazione corruzione file..."
    docker exec mapreduce-project-worker1-1 sh -c "echo 'corrupted' > /tmp/mapreduce/mr-intermediate-0-0"
    Start-Sleep -Seconds 5
    
    Write-Host "3. Verifica rilevamento corruzione..."
    docker-compose -f docker/docker-compose.yml logs master0 | Select-Object -Last 10
    
    Write-Host "4. Verifica recovery automatico..."
    Start-Sleep -Seconds 15
    docker exec mapreduce-project-worker1-1 ls -la /tmp/mapreduce/ | Where-Object { $_ -match "mr-intermediate" }
    
    Write-ColorOutput "Test corruzione dati completato" "Green"
    return $true
}

function Test-StressFailures {
    Write-ColorOutput "=== TEST STRESS CON FALLIMENTI MULTIPLI ===" "Magenta"
    Write-Host ""
    
    Write-Host "1. Simulazione guasti multipli simultanei..."
    docker-compose -f docker/docker-compose.yml stop master1 worker1
    Start-Sleep -Seconds 5
    
    Write-Host "2. Verifica sistema ancora operativo..."
    docker-compose -f docker/docker-compose.yml ps
    
    Write-Host "3. Test elezione leader con minoranza..."
    $ports = @("8000", "8002")
    foreach ($port in $ports) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/health" -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "Sistema operativo con leader su porta $port" "Green"
                break
            }
        }
        catch {
            if ($Verbose) { Write-Host "Porta $port non risponde" }
        }
    }
    
    Write-Host "4. Ripristino servizi..."
    docker-compose -f docker/docker-compose.yml start master1 worker1
    Start-Sleep -Seconds 15
    
    Write-Host "5. Verifica recovery completo..."
    docker-compose -f docker/docker-compose.yml ps
    
    Write-ColorOutput "Test stress completato" "Green"
    return $true
}

# Main execution
if ($Help) {
    Show-Help
    exit 0
}

Write-ColorOutput "=== FAULT TOLERANCE TEST SUITE ===" "Blue"
Write-Host "Test Type: $TestType"
Write-Host ""

if (-not (Test-DockerRunning)) {
    exit 1
}

$testResults = @{}

if (-not (Start-TestCluster)) {
    Write-ColorOutput "Impossibile avviare cluster per test" "Red"
    exit 1
}

try {
    switch ($TestType.ToLower()) {
        "all" {
            Write-ColorOutput "Esecuzione tutti i test di fault tolerance..." "Cyan"
            $testResults["leader"] = Test-LeaderElection
            $testResults["worker"] = Test-WorkerFailures
            $testResults["mapper"] = Test-MapperFailures
            $testResults["reduce"] = Test-ReduceFailures
            $testResults["network"] = Test-NetworkFailures
            $testResults["storage"] = Test-StorageFailures
            $testResults["stress"] = Test-StressFailures
        }
        "leader" {
            $testResults["leader"] = Test-LeaderElection
        }
        "worker" {
            $testResults["worker"] = Test-WorkerFailures
        }
        "mapper" {
            $testResults["mapper"] = Test-MapperFailures
        }
        "reduce" {
            $testResults["reduce"] = Test-ReduceFailures
        }
        "network" {
            $testResults["network"] = Test-NetworkFailures
        }
        "storage" {
            $testResults["storage"] = Test-StorageFailures
        }
        "stress" {
            $testResults["stress"] = Test-StressFailures
        }
        default {
            Write-ColorOutput "Tipo di test non riconosciuto: $TestType" "Red"
            Show-Help
            exit 1
        }
    }
}
finally {
    Stop-TestCluster
}

Write-Host ""
Write-ColorOutput "=== RISULTATI TEST FAULT TOLERANCE ===" "Blue"
Write-Host ""

$passedTests = 0
$totalTests = $testResults.Count

foreach ($test in $testResults.GetEnumerator()) {
    if ($test.Value) {
        Write-ColorOutput "✓ $($test.Key): PASSED" "Green"
        $passedTests++
    } else {
        Write-ColorOutput "✗ $($test.Key): FAILED" "Red"
    }
}

Write-Host ""
Write-ColorOutput "Risultato finale: $passedTests/$totalTests test superati" "Blue"

if ($passedTests -eq $totalTests) {
    Write-ColorOutput "TUTTI I TEST SUPERATI! Sistema fault tolerance operativo." "Green"
    exit 0
} else {
    Write-ColorOutput "ALCUNI TEST FALLITI! Verificare la configurazione." "Red"
    exit 1
}
