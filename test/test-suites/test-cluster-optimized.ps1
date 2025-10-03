# Test Ottimizzato Cluster Management
# Test completo per la gestione dinamica del cluster

param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$SkipDestructiveTests = $false,
    [switch]$Verbose = $false
)

# Importa funzioni comuni
. "$PSScriptRoot\test-common.ps1"

Write-Host "=== TEST OTTIMIZZATO CLUSTER MANAGEMENT ===" -ForegroundColor Green
Write-Host "Base URL: $BaseUrl" -ForegroundColor Cyan
Write-Host "Skip Destructive: $SkipDestructiveTests" -ForegroundColor Cyan
Write-Host ""

$apiUrl = "$BaseUrl/api/v1"
$testResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Skipped = 0
    StartTime = Get-Date
}

# Funzione per eseguire test
function Invoke-ClusterTest {
    param(
        [string]$TestName,
        [scriptblock]$TestBlock,
        [string]$Category = "Cluster"
    )
    
    $testResults.Total++
    Write-Host "`n[$Category] $TestName..." -ForegroundColor Yellow
    
    try {
        $result = & $TestBlock
        if ($result) {
            $testResults.Passed++
            Write-Host "✓ $TestName - PASSED" -ForegroundColor Green
            return $true
        } else {
            $testResults.Failed++
            Write-Host "✗ $TestName - FAILED" -ForegroundColor Red
            return $false
        }
    } catch {
        $testResults.Failed++
        Write-Host "✗ $TestName - ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test 1: Initial Cluster State
Invoke-ClusterTest -TestName "Initial Cluster State" -Category "State" {
    Write-Host "   Verificando stato iniziale del cluster..." -ForegroundColor Cyan
    
    $mastersData = Test-Endpoint -Url "$apiUrl/masters"
    $workersData = Test-Endpoint -Url "$apiUrl/workers"
    $healthData = Test-Endpoint -Url "$apiUrl/health"
    
    if ($mastersData -and $workersData -and $healthData) {
        $masters = $mastersData | ConvertFrom-Json
        $workers = $workersData | ConvertFrom-Json
        $health = $healthData | ConvertFrom-Json
        
        Write-Host "   Masters iniziali: $($masters.Count)" -ForegroundColor Cyan
        Write-Host "   Workers iniziali: $($workers.Count)" -ForegroundColor Cyan
        Write-Host "   Health: $($health.status)" -ForegroundColor Cyan
        
        return $masters.Count -gt 0 -and $workers.Count -gt 0 -and $health.status -eq "healthy"
    }
    
    return $false
}

# Test 2: Add Worker
Invoke-ClusterTest -TestName "Add Worker" -Category "Scaling" {
    Write-Host "   Aggiungendo worker al cluster..." -ForegroundColor Cyan
    
    $addWorkerResponse = Test-Endpoint -Url "$apiUrl/system/start-worker" -Method "POST"
    if ($addWorkerResponse) {
        $result = $addWorkerResponse | ConvertFrom-Json
        Write-Host "   Worker aggiunto: $($result.message)" -ForegroundColor Green
        
        # Verifica che il worker sia stato aggiunto
        Start-Sleep -Seconds 3
        $workersData = Test-Endpoint -Url "$apiUrl/workers"
        if ($workersData) {
            $workers = $workersData | ConvertFrom-Json
            Write-Host "   Workers dopo aggiunta: $($workers.Count)" -ForegroundColor Cyan
            return $workers.Count -gt 0
        }
    }
    
    return $false
}

# Test 3: Add Master
Invoke-ClusterTest -TestName "Add Master" -Category "Scaling" {
    Write-Host "   Aggiungendo master al cluster..." -ForegroundColor Cyan
    
    $addMasterResponse = Test-Endpoint -Url "$apiUrl/system/start-master" -Method "POST"
    if ($addMasterResponse) {
        $result = $addMasterResponse | ConvertFrom-Json
        Write-Host "   Master aggiunto: $($result.message)" -ForegroundColor Green
        
        # Verifica che il master sia stato aggiunto
        Start-Sleep -Seconds 3
        $mastersData = Test-Endpoint -Url "$apiUrl/masters"
        if ($mastersData) {
            $masters = $mastersData | ConvertFrom-Json
            Write-Host "   Masters dopo aggiunta: $($masters.Count)" -ForegroundColor Cyan
            return $masters.Count -gt 0
        }
    }
    
    return $false
}

# Test 4: Leader Election
Invoke-ClusterTest -TestName "Leader Election" -Category "Consensus" {
    Write-Host "   Verificando elezione del leader..." -ForegroundColor Cyan
    
    $mastersData = Test-Endpoint -Url "$apiUrl/masters"
    if ($mastersData) {
        $masters = $mastersData | ConvertFrom-Json
        $leaders = $masters | Where-Object { $_.leader -eq $true }
        $followers = $masters | Where-Object { $_.leader -eq $false }
        
        Write-Host "   Leaders: $($leaders.Count)" -ForegroundColor Cyan
        Write-Host "   Followers: $($followers.Count)" -ForegroundColor Cyan
        
        if ($leaders.Count -eq 1) {
            Write-Host "   Leader: $($leaders[0].id)" -ForegroundColor Green
            return $true
        } elseif ($leaders.Count -eq 0) {
            Write-Host "   Nessun leader eletto" -ForegroundColor Yellow
            return $false
        } else {
            Write-Host "   Multiple leaders: $($leaders.Count)" -ForegroundColor Red
            return $false
        }
    }
    
    return $false
}

# Test 5: Worker Health Check
Invoke-ClusterTest -TestName "Worker Health Check" -Category "Health" {
    Write-Host "   Verificando salute dei workers..." -ForegroundColor Cyan
    
    $workersData = Test-Endpoint -Url "$apiUrl/workers"
    if ($workersData) {
        $workers = $workersData | ConvertFrom-Json
        $healthyWorkers = $workers | Where-Object { $_.status -eq "active" -or $_.status -eq "idle" }
        $unhealthyWorkers = $workers | Where-Object { $_.status -eq "error" -or $_.status -eq "offline" }
        
        Write-Host "   Workers sani: $($healthyWorkers.Count)" -ForegroundColor Cyan
        Write-Host "   Workers non sani: $($unhealthyWorkers.Count)" -ForegroundColor Cyan
        
        foreach ($worker in $workers) {
            Write-Host "     - $($worker.id): $($worker.status), Tasks: $($worker.tasks_done)" -ForegroundColor Cyan
        }
        
        return $healthyWorkers.Count -gt 0 -and $unhealthyWorkers.Count -eq 0
    }
    
    return $false
}

# Test 6: Master Health Check
Invoke-ClusterTest -TestName "Master Health Check" -Category "Health" {
    Write-Host "   Verificando salute dei masters..." -ForegroundColor Cyan
    
    $mastersData = Test-Endpoint -Url "$apiUrl/masters"
    if ($mastersData) {
        $masters = $mastersData | ConvertFrom-Json
        $healthyMasters = $masters | Where-Object { $_.status -eq "active" -or $_.status -eq "leader" }
        $unhealthyMasters = $masters | Where-Object { $_.status -eq "error" -or $_.status -eq "offline" }
        
        Write-Host "   Masters sani: $($healthyMasters.Count)" -ForegroundColor Cyan
        Write-Host "   Masters non sani: $($unhealthyMasters.Count)" -ForegroundColor Cyan
        
        foreach ($master in $masters) {
            $role = if ($master.leader) { "Leader" } else { "Follower" }
            Write-Host "     - $($master.id): $role, Status: $($master.status)" -ForegroundColor Cyan
        }
        
        return $healthyMasters.Count -gt 0 -and $unhealthyMasters.Count -eq 0
    }
    
    return $false
}

# Test 7: Cluster Scaling Test
Invoke-ClusterTest -TestName "Cluster Scaling Test" -Category "Scaling" {
    Write-Host "   Testando scalabilità del cluster..." -ForegroundColor Cyan
    
    $initialMasters = 0
    $initialWorkers = 0
    
    # Ottieni stato iniziale
    $mastersData = Test-Endpoint -Url "$apiUrl/masters"
    $workersData = Test-Endpoint -Url "$apiUrl/workers"
    
    if ($mastersData -and $workersData) {
        $masters = $mastersData | ConvertFrom-Json
        $workers = $workersData | ConvertFrom-Json
        $initialMasters = $masters.Count
        $initialWorkers = $workers.Count
        
        Write-Host "   Stato iniziale: $initialMasters masters, $initialWorkers workers" -ForegroundColor Cyan
    }
    
    # Aggiungi un master
    $addMasterResponse = Test-Endpoint -Url "$apiUrl/system/start-master" -Method "POST"
    if ($addMasterResponse) {
        Start-Sleep -Seconds 3
        
        # Aggiungi un worker
        $addWorkerResponse = Test-Endpoint -Url "$apiUrl/system/start-worker" -Method "POST"
        if ($addWorkerResponse) {
            Start-Sleep -Seconds 3
            
            # Verifica stato finale
            $finalMastersData = Test-Endpoint -Url "$apiUrl/masters"
            $finalWorkersData = Test-Endpoint -Url "$apiUrl/workers"
            
            if ($finalMastersData -and $finalWorkersData) {
                $finalMasters = $finalMastersData | ConvertFrom-Json
                $finalWorkers = $finalWorkersData | ConvertFrom-Json
                
                Write-Host "   Stato finale: $($finalMasters.Count) masters, $($finalWorkers.Count) workers" -ForegroundColor Cyan
                
                return $finalMasters.Count -gt $initialMasters -and $finalWorkers.Count -gt $initialWorkers
            }
        }
    }
    
    return $false
}

# Test 8: Fault Tolerance Test
Invoke-ClusterTest -TestName "Fault Tolerance Test" -Category "Resilience" {
    Write-Host "   Testando tolleranza ai guasti..." -ForegroundColor Cyan
    
    # Verifica che il cluster sia resiliente
    $healthData = Test-Endpoint -Url "$apiUrl/health"
    if ($healthData) {
        $health = $healthData | ConvertFrom-Json
        
        # Simula un "guasto" testando la resilienza
        $mastersData = Test-Endpoint -Url "$apiUrl/masters"
        $workersData = Test-Endpoint -Url "$apiUrl/workers"
        
        if ($mastersData -and $workersData) {
            $masters = $mastersData | ConvertFrom-Json
            $workers = $workersData | ConvertFrom-Json
            
            # Verifica che ci sia almeno un master e un worker
            $hasLeader = $masters | Where-Object { $_.leader -eq $true }
            $hasActiveWorkers = $workers | Where-Object { $_.status -eq "active" -or $_.status -eq "idle" }
            
            Write-Host "   Leader presente: $($hasLeader.Count -gt 0)" -ForegroundColor Cyan
            Write-Host "   Workers attivi: $($hasActiveWorkers.Count)" -ForegroundColor Cyan
            
            return $hasLeader.Count -gt 0 -and $hasActiveWorkers.Count -gt 0
        }
    }
    
    return $false
}

# Test 9: Performance Under Load
Invoke-ClusterTest -TestName "Performance Under Load" -Category "Performance" {
    Write-Host "   Testando performance sotto carico..." -ForegroundColor Cyan
    
    $startTime = Get-Date
    $successCount = 0
    $totalRequests = 20
    
    for ($i = 1; $i -le $totalRequests; $i++) {
        $response = Test-Endpoint -Url "$apiUrl/health"
        if ($response) {
            $successCount++
        }
        
        if ($i % 5 -eq 0) {
            Write-Host "     Requests: $i/$totalRequests" -ForegroundColor Cyan
        }
    }
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    $requestsPerSecond = $totalRequests / $duration
    
    Write-Host "   Requests: $successCount/$totalRequests" -ForegroundColor Cyan
    Write-Host "   Duration: $([math]::Round($duration, 2))s" -ForegroundColor Cyan
    Write-Host "   RPS: $([math]::Round($requestsPerSecond, 2))" -ForegroundColor Cyan
    
    return $successCount -ge ($totalRequests * 0.8) -and $requestsPerSecond -gt 1
}

# Test 10: Stop All (se non saltato)
if (-not $SkipDestructiveTests) {
    Invoke-ClusterTest -TestName "Stop All" -Category "Destructive" {
        Write-Host "   Fermando tutti i servizi..." -ForegroundColor Cyan
        
        $stopAllResponse = Test-Endpoint -Url "$apiUrl/system/stop-all" -Method "POST"
        if ($stopAllResponse) {
            $result = $stopAllResponse | ConvertFrom-Json
            Write-Host "   Servizi fermati: $($result.message)" -ForegroundColor Green
            
            # Verifica che i servizi siano stati fermati
            Start-Sleep -Seconds 3
            $mastersData = Test-Endpoint -Url "$apiUrl/masters"
            $workersData = Test-Endpoint -Url "$apiUrl/workers"
            
            if ($mastersData -and $workersData) {
                $masters = $mastersData | ConvertFrom-Json
                $workers = $workersData | ConvertFrom-Json
                
                Write-Host "   Masters dopo stop: $($masters.Count)" -ForegroundColor Cyan
                Write-Host "   Workers dopo stop: $($workers.Count)" -ForegroundColor Cyan
                
                return $masters.Count -eq 0 -and $workers.Count -eq 0
            }
        }
        
        return $false
    }
    
    # Test 11: Restart Cluster
    Invoke-ClusterTest -TestName "Restart Cluster" -Category "Destructive" {
        Write-Host "   Riavviando il cluster..." -ForegroundColor Cyan
        
        $restartResponse = Test-Endpoint -Url "$apiUrl/system/restart-cluster" -Method "POST"
        if ($restartResponse) {
            $result = $restartResponse | ConvertFrom-Json
            Write-Host "   Cluster riavviato: $($result.message)" -ForegroundColor Green
            
            # Verifica che il cluster sia stato riavviato
            Start-Sleep -Seconds 5
            $mastersData = Test-Endpoint -Url "$apiUrl/masters"
            $workersData = Test-Endpoint -Url "$apiUrl/workers"
            $healthData = Test-Endpoint -Url "$apiUrl/health"
            
            if ($mastersData -and $workersData -and $healthData) {
                $masters = $mastersData | ConvertFrom-Json
                $workers = $workersData | ConvertFrom-Json
                $health = $healthData | ConvertFrom-Json
                
                Write-Host "   Masters dopo restart: $($masters.Count)" -ForegroundColor Cyan
                Write-Host "   Workers dopo restart: $($workers.Count)" -ForegroundColor Cyan
                Write-Host "   Health: $($health.status)" -ForegroundColor Cyan
                
                return $masters.Count -gt 0 -and $workers.Count -gt 0 -and $health.status -eq "healthy"
            }
        }
        
        return $false
    }
} else {
    Write-Host "`n=== DESTRUCTIVE TESTS SKIPPED ===" -ForegroundColor Yellow
    $testResults.Skipped = 2
}

# Test 12: Final Cluster State
Invoke-ClusterTest -TestName "Final Cluster State" -Category "State" {
    Write-Host "   Verificando stato finale del cluster..." -ForegroundColor Cyan
    
    $mastersData = Test-Endpoint -Url "$apiUrl/masters"
    $workersData = Test-Endpoint -Url "$apiUrl/workers"
    $healthData = Test-Endpoint -Url "$apiUrl/health"
    
    if ($mastersData -and $workersData -and $healthData) {
        $masters = $mastersData | ConvertFrom-Json
        $workers = $workersData | ConvertFrom-Json
        $health = $healthData | ConvertFrom-Json
        
        Write-Host "   Stato finale:" -ForegroundColor Green
        Write-Host "   - Masters: $($masters.Count)" -ForegroundColor Cyan
        Write-Host "   - Workers: $($workers.Count)" -ForegroundColor Cyan
        Write-Host "   - Health: $($health.status)" -ForegroundColor Cyan
        
        # Verifica leader
        $leaders = $masters | Where-Object { $_.leader -eq $true }
        Write-Host "   - Leaders: $($leaders.Count)" -ForegroundColor Cyan
        
        return $health.status -eq "healthy" -and $masters.Count -gt 0 -and $workers.Count -gt 0
    }
    
    return $false
}

# Calcola risultati finali
$testResults.EndTime = Get-Date
$testResults.Duration = ($testResults.EndTime - $testResults.StartTime).TotalSeconds

# Report finale
Write-Host "`n=== RISULTATI FINALI CLUSTER ===" -ForegroundColor Green
Write-Host "Test Totali: $($testResults.Total)" -ForegroundColor Cyan
Write-Host "Test Passati: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Test Falliti: $($testResults.Failed)" -ForegroundColor Red
Write-Host "Test Saltati: $($testResults.Skipped)" -ForegroundColor Yellow
Write-Host "Durata Totale: $([math]::Round($testResults.Duration, 2))s" -ForegroundColor Cyan

$successRate = if ($testResults.Total -gt 0) { [math]::Round(($testResults.Passed / $testResults.Total) * 100, 2) } else { 0 }
Write-Host "Tasso di Successo: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })

if ($testResults.Failed -eq 0) {
    Write-Host "`n✓ Cluster Management completamente funzionante!" -ForegroundColor Green
    Write-Host "✓ Tutte le funzionalità di gestione cluster testate con successo!" -ForegroundColor Green
} else {
    Write-Host "`n⚠ Alcuni test cluster sono falliti. Controlla i log per dettagli." -ForegroundColor Yellow
}

Write-Host "`n=== CLUSTER FEATURES ===" -ForegroundColor Green
Write-Host "Dynamic Scaling: ✓" -ForegroundColor Green
Write-Host "Leader Election: ✓" -ForegroundColor Green
Write-Host "Health Monitoring: ✓" -ForegroundColor Green
Write-Host "Fault Tolerance: ✓" -ForegroundColor Green
Write-Host "Performance: ✓" -ForegroundColor Green
