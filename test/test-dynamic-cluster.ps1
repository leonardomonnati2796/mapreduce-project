# Test per gestione dinamica cluster MapReduce
# Verifica che si possano aggiungere N master e N worker dinamicamente

Write-Host "=== TEST GESTIONE DINAMICA CLUSTER MAPREDUCE ===" -ForegroundColor Green

# Verifica che il cluster sia in esecuzione
Write-Host "`n1. Verifica stato iniziale cluster..." -ForegroundColor Yellow
$containers = docker ps --filter "name=docker-master" --format "{{.Names}}"
$initialMasters = ($containers | Measure-Object).Count
Write-Host "Master iniziali: $initialMasters"

$containers = docker ps --filter "name=docker-worker" --format "{{.Names}}"
$initialWorkers = ($containers | Measure-Object).Count
Write-Host "Worker iniziali: $initialWorkers"

# Test aggiunta master dinamica
Write-Host "`n2. Test aggiunta master dinamica..." -ForegroundColor Yellow
Write-Host "Aggiungendo master3..."
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/system/start-master" -Method POST
    Write-Host "Risposta: $response"
} catch {
    Write-Host "Errore: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 3

$containers = docker ps --filter "name=docker-master" --format "{{.Names}}"
$newMasters = ($containers | Measure-Object).Count
Write-Host "Master dopo aggiunta: $newMasters"

if ($newMasters -gt $initialMasters) {
    Write-Host "✓ Master aggiunto con successo!" -ForegroundColor Green
} else {
    Write-Host "✗ Errore: Master non aggiunto" -ForegroundColor Red
}

# Test aggiunta worker dinamica
Write-Host "`n3. Test aggiunta worker dinamica..." -ForegroundColor Yellow
Write-Host "Aggiungendo worker4..."
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/api/system/start-worker" -Method POST
    Write-Host "Risposta: $response"
} catch {
    Write-Host "Errore: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 3

$containers = docker ps --filter "name=docker-worker" --format "{{.Names}}"
$newWorkers = ($containers | Measure-Object).Count
Write-Host "Worker dopo aggiunta: $newWorkers"

if ($newWorkers -gt $initialWorkers) {
    Write-Host "✓ Worker aggiunto con successo!" -ForegroundColor Green
} else {
    Write-Host "✗ Errore: Worker non aggiunto" -ForegroundColor Red
}

# Test aggiunta multipla
Write-Host "`n4. Test aggiunta multipla..." -ForegroundColor Yellow
Write-Host "Aggiungendo master4 e worker5..."

try {
    $response1 = Invoke-RestMethod -Uri "http://localhost:8080/api/system/start-master" -Method POST
    Write-Host "Master4: $response1"
} catch {
    Write-Host "Errore Master4: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $response2 = Invoke-RestMethod -Uri "http://localhost:8080/api/system/start-worker" -Method POST
    Write-Host "Worker5: $response2"
} catch {
    Write-Host "Errore Worker5: $($_.Exception.Message)" -ForegroundColor Red
}

    Start-Sleep -Seconds 5

$containers = docker ps --filter "name=docker-master" --format "{{.Names}}"
$finalMasters = ($containers | Measure-Object).Count

$containers = docker ps --filter "name=docker-worker" --format "{{.Names}}"
$finalWorkers = ($containers | Measure-Object).Count

Write-Host "Master finali: $finalMasters"
Write-Host "Worker finali: $finalWorkers"

# Verifica configurazione RAFT
Write-Host "`n5. Verifica configurazione RAFT..." -ForegroundColor Yellow
$master3 = docker ps --filter "name=docker-master3" --format "{{.Names}}"
if ($master3) {
    Write-Host "✓ Master3 trovato: $master3" -ForegroundColor Green
} else {
    Write-Host "✗ Master3 non trovato" -ForegroundColor Red
}

# Test dashboard aggiornamenti
Write-Host "`n6. Test aggiornamenti dashboard..." -ForegroundColor Yellow
try {
    $dashboardData = Invoke-RestMethod -Uri "http://localhost:8080/api/masters" -Method GET
    Write-Host "Master nella dashboard: $($dashboardData.Count)"
    
    $workerData = Invoke-RestMethod -Uri "http://localhost:8080/api/workers" -Method GET
    Write-Host "Worker nella dashboard: $($workerData.Count)"
    
    Write-Host "✓ Dashboard aggiornata correttamente!" -ForegroundColor Green
} catch {
    Write-Host "✗ Errore dashboard: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== TEST COMPLETATO ===" -ForegroundColor Green
Write-Host "Risultati:"
Write-Host "- Master iniziali: $initialMasters"
Write-Host "- Master finali: $finalMasters"
Write-Host "- Worker iniziali: $initialWorkers" 
Write-Host "- Worker finali: $finalWorkers"
Write-Host "- Aggiunti: $($finalMasters - $initialMasters) master, $($finalWorkers - $initialWorkers) worker"