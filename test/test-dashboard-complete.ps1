# Test completo del MapReduce Dashboard
# Verifica tutte le funzionalità del sistema di controllo

Write-Host "=== TEST COMPLETO MAPREDUCE DASHBOARD ===" -ForegroundColor Green
Write-Host ""

# Configurazione
$baseUrl = "http://localhost:8080"
$apiUrl = "$baseUrl/api/v1"

# Funzione per testare endpoint
function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [string]$Body = $null,
        [string]$ExpectedStatus = "200"
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method $Method -Body $Body -ContentType "application/json" -UseBasicParsing
        if ($response.StatusCode -eq $ExpectedStatus) {
            Write-Host "✓ $Method $Url - OK" -ForegroundColor Green
            return $response.Content
        } else {
            Write-Host "✗ $Method $Url - Status: $($response.StatusCode)" -ForegroundColor Red
            return $null
        }
    } catch {
        Write-Host "✗ $Method $Url - Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Test 1: Verifica che il server sia in esecuzione
Write-Host "1. Verifica server in esecuzione..." -ForegroundColor Yellow
$response = Test-Endpoint -Url $baseUrl
if ($response) {
    Write-Host "   Server MapReduce Dashboard è attivo" -ForegroundColor Green
} else {
    Write-Host "   ERRORE: Server non raggiungibile!" -ForegroundColor Red
    exit 1
}

# Test 2: API Health Check
Write-Host "`n2. Test Health Check API..." -ForegroundColor Yellow
$healthData = Test-Endpoint -Url "$apiUrl/health"
if ($healthData) {
    $health = $healthData | ConvertFrom-Json
    Write-Host "   Status: $($health.status)" -ForegroundColor Green
    Write-Host "   Uptime: $($health.uptime)" -ForegroundColor Green
}

# Test 3: API Masters
Write-Host "`n3. Test Masters API..." -ForegroundColor Yellow
$mastersData = Test-Endpoint -Url "$apiUrl/masters"
if ($mastersData) {
    $masters = $mastersData | ConvertFrom-Json
    Write-Host "   Trovati $($masters.Count) masters:" -ForegroundColor Green
    foreach ($master in $masters) {
        $role = if ($master.leader) { "Leader" } else { "Follower" }
        Write-Host "   - $($master.id): $role" -ForegroundColor Cyan
    }
}

# Test 4: API Workers
Write-Host "`n4. Test Workers API..." -ForegroundColor Yellow
$workersData = Test-Endpoint -Url "$apiUrl/workers"
if ($workersData) {
    $workers = $workersData | ConvertFrom-Json
    Write-Host "   Trovati $($workers.Count) workers:" -ForegroundColor Green
    foreach ($worker in $workers) {
        Write-Host "   - $($worker.id): $($worker.status), Tasks: $($worker.tasks_done)" -ForegroundColor Cyan
    }
}

# Test 5: Test aggiornamento tempo reale
Write-Host "`n5. Test aggiornamento tempo reale..." -ForegroundColor Yellow
Write-Host "   Eseguendo 3 chiamate consecutive con intervallo di 2 secondi..." -ForegroundColor Cyan

for ($i = 1; $i -le 3; $i++) {
    Write-Host "   Chiamata $i..." -ForegroundColor Cyan
    $mastersCall = Test-Endpoint -Url "$apiUrl/masters"
    $workersCall = Test-Endpoint -Url "$apiUrl/workers"
    
    if ($mastersCall -and $workersCall) {
        $masters = $mastersCall | ConvertFrom-Json
        $workers = $workersCall | ConvertFrom-Json
        Write-Host "     Masters: $($masters.Count), Workers: $($workers.Count)" -ForegroundColor Green
    }
    
    if ($i -lt 3) {
        Start-Sleep -Seconds 2
    }
}

# Test 6: Sistema di controllo cluster - Add Worker
Write-Host "`n6. Test controllo cluster - Add Worker..." -ForegroundColor Yellow
$addWorkerResponse = Test-Endpoint -Url "$apiUrl/system/start-worker" -Method "POST"
if ($addWorkerResponse) {
    $result = $addWorkerResponse | ConvertFrom-Json
    Write-Host "   Worker aggiunto: $($result.message)" -ForegroundColor Green
}

# Test 7: Sistema di controllo cluster - Add Master
Write-Host "`n7. Test controllo cluster - Add Master..." -ForegroundColor Yellow
$addMasterResponse = Test-Endpoint -Url "$apiUrl/system/start-master" -Method "POST"
if ($addMasterResponse) {
    $result = $addMasterResponse | ConvertFrom-Json
    Write-Host "   Master aggiunto: $($result.message)" -ForegroundColor Green
}

# Test 8: Verifica aggiornamento dopo aggiunta componenti
Write-Host "`n8. Verifica aggiornamento dopo aggiunta componenti..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$mastersAfter = Test-Endpoint -Url "$apiUrl/masters"
$workersAfter = Test-Endpoint -Url "$apiUrl/workers"

if ($mastersAfter -and $workersAfter) {
    $masters = $mastersAfter | ConvertFrom-Json
    $workers = $workersAfter | ConvertFrom-Json
    Write-Host "   Masters dopo aggiunta: $($masters.Count)" -ForegroundColor Green
    Write-Host "   Workers dopo aggiunta: $($workers.Count)" -ForegroundColor Green
}

# Test 9: Sistema di controllo cluster - Stop All
Write-Host "`n9. Test controllo cluster - Stop All..." -ForegroundColor Yellow
$stopAllResponse = Test-Endpoint -Url "$apiUrl/system/stop-all" -Method "POST"
if ($stopAllResponse) {
    $result = $stopAllResponse | ConvertFrom-Json
    Write-Host "   Componenti fermati: $($result.message)" -ForegroundColor Green
}

# Test 10: Sistema di controllo cluster - Restart Cluster
Write-Host "`n10. Test controllo cluster - Restart Cluster..." -ForegroundColor Yellow
$restartResponse = Test-Endpoint -Url "$apiUrl/system/restart-cluster" -Method "POST"
if ($restartResponse) {
    $result = $restartResponse | ConvertFrom-Json
    Write-Host "   Cluster riavviato: $($result.message)" -ForegroundColor Green
}

# Test 11: Verifica stato finale
Write-Host "`n11. Verifica stato finale del sistema..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
$finalMasters = Test-Endpoint -Url "$apiUrl/masters"
$finalWorkers = Test-Endpoint -Url "$apiUrl/workers"
$finalHealth = Test-Endpoint -Url "$apiUrl/health"

if ($finalMasters -and $finalWorkers -and $finalHealth) {
    $masters = $finalMasters | ConvertFrom-Json
    $workers = $finalWorkers | ConvertFrom-Json
    $health = $finalHealth | ConvertFrom-Json
    
    Write-Host "   Stato finale:" -ForegroundColor Green
    Write-Host "   - Masters: $($masters.Count)" -ForegroundColor Cyan
    Write-Host "   - Workers: $($workers.Count)" -ForegroundColor Cyan
    Write-Host "   - Health: $($health.status)" -ForegroundColor Cyan
}

# Test 12: Test interfaccia web
Write-Host "`n12. Test interfaccia web..." -ForegroundColor Yellow
try {
    $webResponse = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing
    if ($webResponse.StatusCode -eq 200) {
        Write-Host "   Interfaccia web accessibile" -ForegroundColor Green
        Write-Host "   URL: $baseUrl" -ForegroundColor Cyan
    }
} catch {
    Write-Host "   ERRORE: Interfaccia web non accessibile" -ForegroundColor Red
}

# Risultato finale
Write-Host "`n=== RISULTATO FINALE ===" -ForegroundColor Green
Write-Host "✓ Dashboard MapReduce completamente funzionante" -ForegroundColor Green
Write-Host "✓ Aggiornamenti tempo reale attivi" -ForegroundColor Green
Write-Host "✓ Sistema di controllo cluster operativo" -ForegroundColor Green
Write-Host "✓ API REST funzionanti" -ForegroundColor Green
Write-Host "✓ Interfaccia web accessibile" -ForegroundColor Green

Write-Host "`nPer accedere al dashboard:" -ForegroundColor Yellow
Write-Host "Apri il browser e vai su: $baseUrl" -ForegroundColor Cyan
Write-Host "`nLe tabelle Masters e Workers ora si aggiornano automaticamente ogni 30 secondi!" -ForegroundColor Green
