# Script semplice per aprire il dashboard MapReduce
Write-Host "🚀 Aprendo MapReduce Dashboard..." -ForegroundColor Green

$DashboardUrl = "http://localhost:8080"

# Verifica se il dashboard è attivo
Write-Host "Verificando dashboard..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri $DashboardUrl -UseBasicParsing -TimeoutSec 3
    Write-Host "✓ Dashboard attivo!" -ForegroundColor Green
} catch {
    Write-Host "⚠ Dashboard non raggiungibile" -ForegroundColor Yellow
    Write-Host "Avvia il dashboard con: .\mapreduce-dashboard.exe dashboard" -ForegroundColor Cyan
}

# Apre il browser
Write-Host "Aprendo browser..." -ForegroundColor Yellow
Start-Process $DashboardUrl
Write-Host "✓ Browser aperto: $DashboardUrl" -ForegroundColor Cyan

Write-Host ""
Write-Host "💡 Comandi utili:" -ForegroundColor Yellow
Write-Host "   .\mapreduce-dashboard.exe dashboard" -ForegroundColor White
Write-Host "   .\mapreduce-dashboard.exe elect-leader" -ForegroundColor White
