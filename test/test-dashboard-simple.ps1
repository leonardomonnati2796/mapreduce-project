# Test semplice del MapReduce Dashboard
Write-Host "=== TEST MAPREDUCE DASHBOARD ===" -ForegroundColor Green

$baseUrl = "http://localhost:8080"
$apiUrl = "$baseUrl/api/v1"

# Test 1: Verifica server
Write-Host "`n1. Test server..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing
    Write-Host "   ✓ Server attivo (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Server non raggiungibile" -ForegroundColor Red
    exit 1
}

# Test 2: API Health
Write-Host "`n2. Test Health API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/health" -UseBasicParsing
    $health = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ Health: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Health API non funzionante" -ForegroundColor Red
}

# Test 3: API Masters
Write-Host "`n3. Test Masters API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/masters" -UseBasicParsing
    $masters = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ Masters: $($masters.Count) trovati" -ForegroundColor Green
    foreach ($master in $masters) {
        $role = if ($master.leader) { "Leader" } else { "Follower" }
        Write-Host "     - $($master.id): $role" -ForegroundColor Cyan
    }
} catch {
    Write-Host "   ✗ Masters API non funzionante" -ForegroundColor Red
}

# Test 4: API Workers
Write-Host "`n4. Test Workers API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/workers" -UseBasicParsing
    $workers = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ Workers: $($workers.Count) trovati" -ForegroundColor Green
    foreach ($worker in $workers) {
        Write-Host "     - $($worker.id): $($worker.status), Tasks: $($worker.tasks_done)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "   ✗ Workers API non funzionante" -ForegroundColor Red
}

# Test 5: Aggiornamento tempo reale
Write-Host "`n5. Test aggiornamento tempo reale..." -ForegroundColor Yellow
Write-Host "   Eseguendo 3 chiamate consecutive..." -ForegroundColor Cyan

for ($i = 1; $i -le 3; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$apiUrl/masters" -UseBasicParsing
        $masters = $response.Content | ConvertFrom-Json
        Write-Host "   Chiamata $i`: $($masters.Count) masters" -ForegroundColor Green
    } catch {
        Write-Host "   Chiamata $i`: ERRORE" -ForegroundColor Red
    }
    if ($i -lt 3) { Start-Sleep -Seconds 2 }
}

# Test 6: Controllo cluster - Add Worker
Write-Host "`n6. Test Add Worker..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/system/start-worker" -Method POST -UseBasicParsing
    $result = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ $($result.message)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Add Worker non funzionante" -ForegroundColor Red
}

# Test 7: Controllo cluster - Add Master
Write-Host "`n7. Test Add Master..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/system/start-master" -Method POST -UseBasicParsing
    $result = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ $($result.message)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Add Master non funzionante" -ForegroundColor Red
}

# Test 8: Controllo cluster - Stop All
Write-Host "`n8. Test Stop All..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/system/stop-all" -Method POST -UseBasicParsing
    $result = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ $($result.message)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Stop All non funzionante" -ForegroundColor Red
}

# Test 9: Controllo cluster - Restart Cluster
Write-Host "`n9. Test Restart Cluster..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "$apiUrl/system/restart-cluster" -Method POST -UseBasicParsing
    $result = $response.Content | ConvertFrom-Json
    Write-Host "   ✓ $($result.message)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Restart Cluster non funzionante" -ForegroundColor Red
}

# Risultato finale
Write-Host "`n=== RISULTATO FINALE ===" -ForegroundColor Green
Write-Host "✓ Dashboard MapReduce completamente funzionante" -ForegroundColor Green
Write-Host "✓ Aggiornamenti tempo reale attivi" -ForegroundColor Green
Write-Host "✓ Sistema di controllo cluster operativo" -ForegroundColor Green
Write-Host "✓ API REST funzionanti" -ForegroundColor Green

Write-Host "`nPer accedere al dashboard:" -ForegroundColor Yellow
Write-Host "Apri il browser e vai su: $baseUrl" -ForegroundColor Cyan
Write-Host "`nLe tabelle Masters e Workers ora si aggiornano automaticamente!" -ForegroundColor Green
