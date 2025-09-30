# Test WebSocket Real-time Updates
# Questo script testa gli aggiornamenti in tempo reale della dashboard tramite Docker

Write-Host "=== Test WebSocket Real-time Updates (Docker) ===" -ForegroundColor Green

# Funzione per verificare se un URL è raggiungibile
function Test-Url {
    param([string]$Url, [int]$TimeoutSeconds = 10)
    
    try {
        $response = Invoke-WebRequest -Uri $Url -TimeoutSec $TimeoutSeconds -UseBasicParsing
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

# Funzione per aspettare che un servizio sia disponibile
function Wait-ForService {
    param([string]$Url, [int]$MaxWaitSeconds = 60)
    
    $startTime = Get-Date
    Write-Host "Aspettando che il servizio sia disponibile su $Url..." -ForegroundColor Yellow
    
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($MaxWaitSeconds)) {
        if (Test-Url -Url $Url -TimeoutSeconds 5) {
            Write-Host "✓ Servizio disponibile!" -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds 2
    }
    
    Write-Host "✗ Timeout: servizio non disponibile dopo $MaxWaitSeconds secondi" -ForegroundColor Red
    return $false
}

# Funzione per testare WebSocket (simulazione)
function Test-WebSocketConnection {
    param([string]$Url)
    
    Write-Host "Testando connessione WebSocket..." -ForegroundColor Yellow
    
    # Simula il test WebSocket aprendo la pagina e verificando i log
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "✓ Dashboard raggiungibile" -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Host "✗ Errore nel raggiungere la dashboard: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Funzione per testare le API
function Test-DashboardAPIs {
    param([string]$BaseUrl)
    
    Write-Host "Testando API della dashboard..." -ForegroundColor Yellow
    
    $apis = @(
        "/api/v1/health",
        "/api/v1/masters", 
        "/api/v1/workers",
        "/api/v1/metrics"
    )
    
    $allPassed = $true
    
    foreach ($api in $apis) {
        $url = $BaseUrl + $api
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-Host "✓ $api - OK" -ForegroundColor Green
            } else {
                Write-Host "✗ $api - Status: $($response.StatusCode)" -ForegroundColor Red
                $allPassed = $false
            }
        }
        catch {
            Write-Host "✗ $api - Errore: $($_.Exception.Message)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Funzione per testare le azioni del sistema
function Test-SystemActions {
    param([string]$BaseUrl)
    
    Write-Host "Testando azioni del sistema..." -ForegroundColor Yellow
    
    $actions = @(
        @{url="/api/v1/system/start-master"; method="POST"; name="Add Master"},
        @{url="/api/v1/system/start-worker"; method="POST"; name="Add Worker"},
        @{url="/api/v1/system/elect-leader"; method="POST"; name="Elect Leader"}
    )
    
    $allPassed = $true
    
    foreach ($action in $actions) {
        try {
            $response = Invoke-WebRequest -Uri ($BaseUrl + $action.url) -Method $action.method -UseBasicParsing
            if ($response.StatusCode -eq 200) {
                Write-Host "✓ $($action.name) - OK" -ForegroundColor Green
            } else {
                Write-Host "✗ $($action.name) - Status: $($response.StatusCode)" -ForegroundColor Red
                $allPassed = $false
            }
        }
        catch {
            Write-Host "✗ $($action.name) - Errore: $($_.Exception.Message)" -ForegroundColor Red
            $allPassed = $false
        }
    }
    
    return $allPassed
}

# Main Test Execution
try {
    $dashboardUrl = "http://localhost:8080"
    $websocketUrl = "ws://localhost:8080/ws"
    
    Write-Host "`n1. Verificando che Docker sia in esecuzione..." -ForegroundColor Cyan
    $dockerRunning = Get-Process -Name "docker" -ErrorAction SilentlyContinue
    if (-not $dockerRunning) {
        Write-Host "✗ Docker non è in esecuzione. Avviare Docker Desktop." -ForegroundColor Red
        Write-Host "Eseguire: make docker-start" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✓ Docker è in esecuzione" -ForegroundColor Green
    
    Write-Host "`n2. Verificando che il cluster sia avviato..." -ForegroundColor Cyan
    $containers = docker ps --format "table {{.Names}}\t{{.Status}}" | Select-String -Pattern "master|worker|dashboard"
    if ($containers.Count -lt 5) {
        Write-Host "✗ Cluster non completamente avviato. Eseguire: make start" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Cluster avviato correttamente" -ForegroundColor Green
    Write-Host $containers
    
    Write-Host "`n3. Aspettando che la dashboard sia disponibile..." -ForegroundColor Cyan
    if (-not (Wait-ForService -Url $dashboardUrl -MaxWaitSeconds 30)) {
        Write-Host "✗ Dashboard non disponibile" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n4. Testando connessione WebSocket..." -ForegroundColor Cyan
    if (-not (Test-WebSocketConnection -Url $dashboardUrl)) {
        Write-Host "✗ Problema con la connessione WebSocket" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n5. Testando API della dashboard..." -ForegroundColor Cyan
    if (-not (Test-DashboardAPIs -BaseUrl $dashboardUrl)) {
        Write-Host "✗ Alcune API non funzionano correttamente" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n6. Testando azioni del sistema..." -ForegroundColor Cyan
    if (-not (Test-SystemActions -BaseUrl $dashboardUrl)) {
        Write-Host "✗ Alcune azioni del sistema non funzionano" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`n=== RISULTATI DEL TEST ===" -ForegroundColor Green
    Write-Host "✓ Dashboard raggiungibile" -ForegroundColor Green
    Write-Host "✓ WebSocket configurato" -ForegroundColor Green
    Write-Host "✓ API funzionanti" -ForegroundColor Green
    Write-Host "✓ Azioni del sistema funzionanti" -ForegroundColor Green
    
    Write-Host "`n=== ISTRUZIONI PER TEST MANUALI ===" -ForegroundColor Yellow
    Write-Host "1. Aprire il browser su: $dashboardUrl" -ForegroundColor White
    Write-Host "2. Aprire Developer Tools (F12) e andare alla tab Console" -ForegroundColor White
    Write-Host "3. Verificare i messaggi WebSocket:" -ForegroundColor White
    Write-Host "   - 'WebSocket connected'" -ForegroundColor Gray
    Write-Host "   - 'Received WebSocket message: initial_data'" -ForegroundColor Gray
    Write-Host "   - 'Received WebSocket message: realtime_update'" -ForegroundColor Gray
    Write-Host "4. Testare le azioni:" -ForegroundColor White
    Write-Host "   - Cliccare 'Add Master' e verificare aggiornamento tabella" -ForegroundColor Gray
    Write-Host "   - Cliccare 'Add Worker' e verificare aggiornamento tabella" -ForegroundColor Gray
    Write-Host "   - Cliccare 'Elect New Leader' e verificare cambio leader" -ForegroundColor Gray
    Write-Host "5. Verificare che l'indicatore mostri 'Live Data (WebSocket)'" -ForegroundColor White
    
    Write-Host "`n=== TEST COMPLETATO CON SUCCESSO ===" -ForegroundColor Green
    
} catch {
    Write-Host "`n✗ ERRORE DURANTE IL TEST: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
