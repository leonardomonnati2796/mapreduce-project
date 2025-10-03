# Test Runner Ottimizzato MapReduce
# Esegue tutti i test con configurazione avanzata

param(
    [string]$Environment = "local",
    [string[]]$Categories = @("core", "raft", "integration", "dashboard", "websocket", "cluster"),
    [switch]$Parallel = $true,
    [switch]$Verbose = $false,
    [switch]$GenerateReport = $true,
    [string]$OutputFormat = "console",
    [int]$MaxConcurrentTests = 3,
    [int]$Timeout = 300
)

# Importa funzioni comuni
. "$PSScriptRoot\test-suites\test-common.ps1"

Write-Host "=== TEST RUNNER OTTIMIZZATO MAPREDUCE ===" -ForegroundColor Green
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "Categories: $($Categories -join ', ')" -ForegroundColor Cyan
Write-Host "Parallel: $Parallel" -ForegroundColor Cyan
Write-Host "Max Concurrent: $MaxConcurrentTests" -ForegroundColor Cyan
Write-Host ""

# Carica configurazione
$configPath = "$PSScriptRoot\config\test-config-optimized.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath | ConvertFrom-Json
    Write-Host "✓ Configurazione caricata" -ForegroundColor Green
} else {
    Write-Host "⚠ Configurazione non trovata, usando valori di default" -ForegroundColor Yellow
    $config = @{
        execution = @{
            parallel = $Parallel
            maxConcurrentTests = $MaxConcurrentTests
            timeout = $Timeout
        }
        environments = @{
            local = @{
                baseUrl = "http://localhost:8080"
                apiUrl = "http://localhost:8080/api/v1"
            }
        }
    }
}

# Configura ambiente
$envConfig = $config.environments.$Environment
if ($envConfig) {
    $baseUrl = $envConfig.baseUrl
    $apiUrl = $envConfig.apiUrl
    $timeout = $envConfig.timeout
} else {
    $baseUrl = "http://localhost:8080"
    $apiUrl = "http://localhost:8080/api/v1"
    $timeout = 30
}

Write-Host "Base URL: $baseUrl" -ForegroundColor Cyan
Write-Host "API URL: $apiUrl" -ForegroundColor Cyan
Write-Host "Timeout: $timeout" -ForegroundColor Cyan
Write-Host ""

# Risultati globali
$globalResults = @{
    StartTime = Get-Date
    TotalTests = 0
    PassedTests = 0
    FailedTests = 0
    SkippedTests = 0
    Categories = @{}
    Performance = @{
        TotalDuration = 0
        AverageResponseTime = 0
        MaxResponseTime = 0
        MinResponseTime = [double]::MaxValue
    }
}

# Funzione per eseguire test
function Invoke-TestCategory {
    param(
        [string]$Category,
        [string]$TestFile,
        [string]$Description
    )
    
    Write-Host "`n=== $Category ===" -ForegroundColor Magenta
    Write-Host "File: $TestFile" -ForegroundColor Cyan
    Write-Host "Description: $Description" -ForegroundColor Cyan
    
    $categoryResults = @{
        StartTime = Get-Date
        Passed = 0
        Failed = 0
        Skipped = 0
        Total = 0
    }
    
    try {
        if (Test-Path $TestFile) {
            Write-Host "Eseguendo $TestFile..." -ForegroundColor Yellow
            
            # Esegui test con parametri
            $testParams = @{
                BaseUrl = $baseUrl
                Verbose = $Verbose
            }
            
            # Aggiungi parametri specifici per categoria
            switch ($Category) {
                "cluster" { $testParams.SkipDestructiveTests = $false }
                "websocket" { $testParams.TestDuration = 30 }
            }
            
            $result = & $TestFile @testParams
            
            $categoryResults.EndTime = Get-Date
            $categoryResults.Duration = ($categoryResults.EndTime - $categoryResults.StartTime).TotalSeconds
            
            Write-Host "✓ $Category completato in $([math]::Round($categoryResults.Duration, 2))s" -ForegroundColor Green
        } else {
            Write-Host "✗ File test non trovato: $TestFile" -ForegroundColor Red
            $categoryResults.Failed = 1
        }
    } catch {
        Write-Host "✗ Errore durante esecuzione $Category`: $($_.Exception.Message)" -ForegroundColor Red
        $categoryResults.Failed = 1
    }
    
    $globalResults.Categories[$Category] = $categoryResults
    $globalResults.TotalTests += $categoryResults.Total
    $globalResults.PassedTests += $categoryResults.Passed
    $globalResults.FailedTests += $categoryResults.Failed
    $globalResults.SkippedTests += $categoryResults.Skipped
    
    return $categoryResults
}

# Mappa test per categoria
$testMap = @{
    "core" = @{
        File = "test-suites\test-core-functions.ps1"
        Description = "Test funzioni core MapReduce"
    }
    "raft" = @{
        File = "test-suites\test-raft-consensus.ps1"
        Description = "Test consenso Raft"
    }
    "integration" = @{
        File = "test-suites\test-integration.ps1"
        Description = "Test integrazione completa"
    }
    "dashboard" = @{
        File = "test-suites\test-dashboard-optimized.ps1"
        Description = "Test dashboard web"
    }
    "websocket" = @{
        File = "test-suites\test-websocket-optimized.ps1"
        Description = "Test WebSocket real-time"
    }
    "cluster" = @{
        File = "test-suites\test-cluster-optimized.ps1"
        Description = "Test gestione cluster"
    }
}

# Esegui test
if ($Parallel -and $MaxConcurrentTests -gt 1) {
    Write-Host "Esecuzione parallela con max $MaxConcurrentTests test concorrenti" -ForegroundColor Yellow
    
    $jobs = @()
    foreach ($category in $Categories) {
        if ($testMap.ContainsKey($category)) {
            $testInfo = $testMap[$category]
            $job = Start-Job -ScriptBlock {
                param($TestFile, $BaseUrl, $Verbose, $Category)
                & $TestFile -BaseUrl $BaseUrl -Verbose:$Verbose
            } -ArgumentList $testInfo.File, $baseUrl, $Verbose, $category
            
            $jobs += $job
            
            if ($jobs.Count -ge $MaxConcurrentTests) {
                # Attendi completamento di alcuni job
                $completedJobs = $jobs | Where-Object { $_.State -eq "Completed" -or $_.State -eq "Failed" }
                foreach ($job in $completedJobs) {
                    $result = Receive-Job -Job $job
                    Remove-Job -Job $job
                    $jobs = $jobs | Where-Object { $_ -ne $job }
                }
            }
        }
    }
    
    # Attendi completamento di tutti i job
    $jobs | Wait-Job | Out-Null
    foreach ($job in $jobs) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job
    }
} else {
    Write-Host "Esecuzione sequenziale" -ForegroundColor Yellow
    
    foreach ($category in $Categories) {
        if ($testMap.ContainsKey($category)) {
            $testInfo = $testMap[$category]
            Invoke-TestCategory -Category $category -TestFile $testInfo.File -Description $testInfo.Description
        }
    }
}

# Calcola risultati finali
$globalResults.EndTime = Get-Date
$globalResults.TotalDuration = ($globalResults.EndTime - $globalResults.StartTime).TotalSeconds

# Report finale
Write-Host "`n=== RISULTATI FINALI ===" -ForegroundColor Green
Write-Host "Durata Totale: $([math]::Round($globalResults.TotalDuration, 2))s" -ForegroundColor Cyan
Write-Host "Test Totali: $($globalResults.TotalTests)" -ForegroundColor Cyan
Write-Host "Test Passati: $($globalResults.PassedTests)" -ForegroundColor Green
Write-Host "Test Falliti: $($globalResults.FailedTests)" -ForegroundColor Red
Write-Host "Test Saltati: $($globalResults.SkippedTests)" -ForegroundColor Yellow

$successRate = if ($globalResults.TotalTests -gt 0) { 
    [math]::Round(($globalResults.PassedTests / $globalResults.TotalTests) * 100, 2) 
} else { 0 }

Write-Host "Tasso di Successo: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 70) { "Yellow" } else { "Red" })

# Report per categoria
Write-Host "`n=== RISULTATI PER CATEGORIA ===" -ForegroundColor Green
foreach ($category in $globalResults.Categories.Keys) {
    $results = $globalResults.Categories[$category]
    $categorySuccessRate = if ($results.Total -gt 0) { 
        [math]::Round(($results.Passed / $results.Total) * 100, 2) 
    } else { 0 }
    
    Write-Host "$category`: $($results.Passed)/$($results.Total) ($categorySuccessRate%) - $([math]::Round($results.Duration, 2))s" -ForegroundColor $(if ($categorySuccessRate -ge 90) { "Green" } elseif ($categorySuccessRate -ge 70) { "Yellow" } else { "Red" })
}

# Genera report se richiesto
if ($GenerateReport) {
    Write-Host "`nGenerando report..." -ForegroundColor Yellow
    
    $reportDir = "reports"
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    
    $reportFile = "$reportDir\test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $globalResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-Host "✓ Report generato: $reportFile" -ForegroundColor Green
}

# Exit code basato sui risultati
if ($globalResults.FailedTests -eq 0) {
    Write-Host "`n✓ Tutti i test sono passati!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n⚠ Alcuni test sono falliti!" -ForegroundColor Yellow
    exit 1
}
