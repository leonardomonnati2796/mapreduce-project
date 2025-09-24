# Script rapido per aprire il dashboard MapReduce
# Versione semplificata senza parametri

Write-Host "🚀 Aprendo MapReduce Dashboard..." -ForegroundColor Green

$DashboardUrl = "http://localhost:8080"

# Verifica rapida se il dashboard è attivo
try {
    $response = Invoke-WebRequest -Uri $DashboardUrl -UseBasicParsing -TimeoutSec 3
    Write-Host "✓ Dashboard attivo!" -ForegroundColor Green
} catch {
    Write-Host "⚠ Dashboard non raggiungibile - verificare che sia in esecuzione" -ForegroundColor Yellow
}

# Apre il browser
Start-Process $DashboardUrl
Write-Host "✓ Browser aperto: $DashboardUrl" -ForegroundColor Cyan

Write-Host ""
Write-Host "💡 Per avviare il dashboard:" -ForegroundColor Yellow
Write-Host "   .\mapreduce-dashboard.exe dashboard" -ForegroundColor White
Write-Host ""
Write-Host "💡 Per elezione leader:" -ForegroundColor Yellow
Write-Host "   .\mapreduce-dashboard.exe elect-leader" -ForegroundColor White
