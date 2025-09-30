# Test per comando restart cluster
Write-Host "=== TEST RESTART CLUSTER ===" -ForegroundColor Green

# Verifica stato iniziale
Write-Host "`n1. Stato iniziale cluster..." -ForegroundColor Yellow
$initialContainers = docker ps --filter "name=docker-" --format "{{.Names}}"
Write-Host "Container iniziali: $($initialContainers.Count)"
$initialContainers | ForEach-Object { Write-Host "  $_" }

# Test restart cluster
Write-Host "`n2. Test restart cluster..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/system/restart-cluster" -Method POST
    Write-Host "Risposta restart: $response"
} catch {
    Write-Host "Errore restart: $($_.Exception.Message)" -ForegroundColor Red
}

# Attendi che il cluster si riavvii
Write-Host "`n3. Attesa riavvio cluster (10 secondi)..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verifica stato finale
Write-Host "`n4. Stato finale cluster..." -ForegroundColor Yellow
$finalContainers = docker ps --filter "name=docker-" --format "{{.Names}}"
Write-Host "Container finali: $($finalContainers.Count)"
$finalContainers | ForEach-Object { Write-Host "  $_" }

# Verifica dashboard
Write-Host "`n5. Verifica dashboard..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:8080/api/v1/health" -Method GET
    Write-Host "Dashboard health: $($health.status)"
} catch {
    Write-Host "Errore dashboard: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== TEST COMPLETATO ===" -ForegroundColor Green
Write-Host "Container iniziali: $($initialContainers.Count)"
Write-Host "Container finali: $($finalContainers.Count)"
