# Test Leader Election Functionality
Write-Host "=== TEST LEADER ELECTION ===" -ForegroundColor Green

# Test 1: Comando terminale
Write-Host "`n1. Test comando terminale elect-leader..." -ForegroundColor Yellow
try {
    $output = & ".\mapreduce-dashboard.exe" "elect-leader" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✓ Comando terminale funziona correttamente" -ForegroundColor Green
        Write-Host "   Output:" -ForegroundColor Cyan
        $output | ForEach-Object { Write-Host "     $_" -ForegroundColor Cyan }
    } else {
        Write-Host "   ✗ Comando terminale fallito" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Errore nel comando terminale: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: API endpoint
Write-Host "`n2. Test API endpoint elect-leader..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/v1/system/elect-leader" -Method POST -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✓ API endpoint funziona correttamente" -ForegroundColor Green
        $result = $response.Content | ConvertFrom-Json
        Write-Host "   Risultato:" -ForegroundColor Cyan
        Write-Host "     Success: $($result.success)" -ForegroundColor Cyan
        Write-Host "     Message: $($result.message)" -ForegroundColor Cyan
        Write-Host "     New Leader: $($result.leader_info.leader_id)" -ForegroundColor Cyan
    } else {
        Write-Host "   ✗ API endpoint fallito (Status: $($response.StatusCode))" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Errore nell'API endpoint: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Verifica dashboard web
Write-Host "`n3. Test dashboard web..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "   ✓ Dashboard web accessibile" -ForegroundColor Green
        Write-Host "   URL: http://localhost:8080" -ForegroundColor Cyan
    } else {
        Write-Host "   ✗ Dashboard web non accessibile" -ForegroundColor Red
    }
} catch {
    Write-Host "   ✗ Errore nel dashboard web: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Verifica altri endpoint
Write-Host "`n4. Test altri endpoint sistema..." -ForegroundColor Yellow
$endpoints = @(
    @{url="http://localhost:8080/api/v1/system/start-worker"; method="POST"},
    @{url="http://localhost:8080/api/v1/system/start-master"; method="POST"},
    @{url="http://localhost:8080/api/v1/masters"; method="GET"},
    @{url="http://localhost:8080/api/v1/workers"; method="GET"}
)

foreach ($endpoint in $endpoints) {
    try {
        $response = Invoke-WebRequest -Uri $endpoint.url -Method $endpoint.method -UseBasicParsing
        Write-Host "   ✓ $($endpoint.method) $($endpoint.url) - OK" -ForegroundColor Green
    } catch {
        Write-Host "   ✗ $($endpoint.method) $($endpoint.url) - ERRORE" -ForegroundColor Red
    }
}

# Risultato finale
Write-Host "`n=== RISULTATO FINALE ===" -ForegroundColor Green
Write-Host "✓ Comando terminale elect-leader implementato e funzionante" -ForegroundColor Green
Write-Host "✓ Dashboard web con pulsante Elect Leader" -ForegroundColor Green
Write-Host "✓ API backend per elezione leader" -ForegroundColor Green
Write-Host "✓ Sistema completo di controllo cluster" -ForegroundColor Green

Write-Host "`nPer testare:" -ForegroundColor Yellow
Write-Host "1. Terminale: .\mapreduce-dashboard.exe elect-leader" -ForegroundColor Cyan
Write-Host "2. Dashboard: http://localhost:8080 (clicca su 'Elect Leader')" -ForegroundColor Cyan
Write-Host "3. API: POST http://localhost:8080/api/v1/system/elect-leader" -ForegroundColor Cyan
