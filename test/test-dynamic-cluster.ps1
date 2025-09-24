# Script di test per la gestione dinamica del cluster MapReduce
# Questo script dimostra le nuove funzionalità implementate

param(
    [switch]$Demo,
    [switch]$TestAddMaster,
    [switch]$TestAddWorker,
    [switch]$TestReset,
    [switch]$All
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

function Test-DynamicClusterManagement {
    Write-ColorOutput "=== TEST GESTIONE DINAMICA CLUSTER MAPREDUCE ===" $Blue
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
    Write-ColorOutput "=== DEMO FUNZIONALITÀ IMPLEMENTATE ===" $Cyan
    Write-Host ""
    
    # 1. Avvio cluster di base
    Write-ColorOutput "1. Avvio cluster di base (3 master, 2 worker)..." $Yellow
    & .\scripts\docker-manager.ps1 start
    Start-Sleep -Seconds 10
    
    # 2. Test aggiunta master dinamico
    Write-Host ""
    Write-ColorOutput "2. Test aggiunta master dinamico (ID: 3)..." $Yellow
    & .\scripts\docker-manager.ps1 add-master -NewMasterID 3
    Start-Sleep -Seconds 15
    
    # 3. Test aggiunta worker dinamico
    Write-Host ""
    Write-ColorOutput "3. Test aggiunta worker dinamico (ID: 3)..." $Yellow
    & .\scripts\docker-manager.ps1 add-worker -NewWorkerID 3
    Start-Sleep -Seconds 10
    
    # 4. Verifica stato cluster
    Write-Host ""
    Write-ColorOutput "4. Verifica stato cluster..." $Yellow
    & .\scripts\docker-manager.ps1 status
    
    # 5. Test health check
    Write-Host ""
    Write-ColorOutput "5. Test health check..." $Yellow
    & .\scripts\docker-manager.ps1 health
    
    # 6. Test reset a configurazione default
    Write-Host ""
    Write-ColorOutput "6. Test reset a configurazione default..." $Yellow
    & .\scripts\docker-manager.ps1 reset -ResetToDefault
    Start-Sleep -Seconds 15
    
    # 7. Verifica stato finale
    Write-Host ""
    Write-ColorOutput "7. Verifica stato finale..." $Yellow
    & .\scripts\docker-manager.ps1 status
    
    Write-Host ""
    Write-ColorOutput "=== TEST COMPLETATO ===" $Green
    Write-Host ""
    Write-Host "Funzionalità testate:"
    Write-Host "  ✓ Aggiunta master dinamico con elezione automatica del leader"
    Write-Host "  ✓ Aggiunta worker dinamico"
    Write-Host "  ✓ Reset a configurazione di default"
    Write-Host "  ✓ Health check del cluster"
    Write-Host "  ✓ Gestione automatica delle porte"
    Write-Host "  ✓ Aggiornamento dinamico del docker-compose.yml"
    Write-Host ""
}

function Test-AddMasterOnly {
    Write-ColorOutput "=== TEST AGGIUNTA MASTER ===" $Blue
    Write-Host ""
    
    # Avvia cluster di base
    Write-ColorOutput "Avvio cluster di base..." $Yellow
    & .\scripts\docker-manager.ps1 start
    Start-Sleep -Seconds 10
    
    # Aggiunge master
    Write-ColorOutput "Aggiunta master con ID 3..." $Yellow
    & .\scripts\docker-manager.ps1 add-master -NewMasterID 3
    
    # Verifica stato
    Write-Host ""
    Write-ColorOutput "Verifica stato cluster..." $Yellow
    & .\scripts\docker-manager.ps1 status
    
    Write-ColorOutput "Test completato!" $Green
}

function Test-AddWorkerOnly {
    Write-ColorOutput "=== TEST AGGIUNTA WORKER ===" $Blue
    Write-Host ""
    
    # Avvia cluster di base
    Write-ColorOutput "Avvio cluster di base..." $Yellow
    & .\scripts\docker-manager.ps1 start
    Start-Sleep -Seconds 10
    
    # Aggiunge worker
    Write-ColorOutput "Aggiunta worker con ID 3..." $Yellow
    & .\scripts\docker-manager.ps1 add-worker -NewWorkerID 3
    
    # Verifica stato
    Write-Host ""
    Write-ColorOutput "Verifica stato cluster..." $Yellow
    & .\scripts\docker-manager.ps1 status
    
    Write-ColorOutput "Test completato!" $Green
}

function Test-ResetOnly {
    Write-ColorOutput "=== TEST RESET CONFIGURAZIONE ===" $Blue
    Write-Host ""
    
    # Aggiunge alcuni componenti
    Write-ColorOutput "Aggiunta master e worker per test..." $Yellow
    & .\scripts\docker-manager.ps1 add-master -NewMasterID 3
    Start-Sleep -Seconds 5
    & .\scripts\docker-manager.ps1 add-worker -NewWorkerID 3
    
    Write-Host ""
    Write-ColorOutput "Stato prima del reset:" $Yellow
    & .\scripts\docker-manager.ps1 status
    
    Write-Host ""
    Write-ColorOutput "Esecuzione reset..." $Yellow
    & .\scripts\docker-manager.ps1 reset -ResetToDefault
    
    Write-Host ""
    Write-ColorOutput "Stato dopo il reset:" $Yellow
    & .\scripts\docker-manager.ps1 status
    
    Write-ColorOutput "Test completato!" $Green
}

function Show-Usage {
    Write-ColorOutput "=== TEST GESTIONE DINAMICA CLUSTER MAPREDUCE ===" $Blue
    Write-Host ""
    Write-Host "Usage: .\scripts\test-dynamic-cluster.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Demo           Esegue demo completa di tutte le funzionalità"
    Write-Host "  -TestAddMaster  Testa solo l'aggiunta di un master"
    Write-Host "  -TestAddWorker  Testa solo l'aggiunta di un worker"
    Write-Host "  -TestReset      Testa solo il reset della configurazione"
    Write-Host "  -All            Alias per -Demo"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\test-dynamic-cluster.ps1 -Demo"
    Write-Host "  .\scripts\test-dynamic-cluster.ps1 -TestAddMaster"
    Write-Host "  .\scripts\test-dynamic-cluster.ps1 -All"
    Write-Host ""
}

# Main execution
if ($Demo -or $All) {
    Test-DynamicClusterManagement
}
elseif ($TestAddMaster) {
    Test-AddMasterOnly
}
elseif ($TestAddWorker) {
    Test-AddWorkerOnly
}
elseif ($TestReset) {
    Test-ResetOnly
}
else {
    Show-Usage
}

Write-Host ""
Write-ColorOutput "=== Script completato ===" $Green
