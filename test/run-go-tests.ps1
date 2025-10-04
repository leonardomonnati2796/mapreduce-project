# Script per eseguire i test Go dalla cartella test
# Questo script deve essere eseguito dalla directory principale del progetto

Write-Host "🧪 Eseguendo test Go dalla cartella test..." -ForegroundColor Green

# Cambia alla directory principale
$originalDir = Get-Location
Set-Location ..

Write-Host "📁 Directory corrente: $(Get-Location)" -ForegroundColor Yellow

# Esegui i test load balancer
Write-Host "`n📊 Eseguendo test Load Balancer..." -ForegroundColor Cyan
go test -v ./test/loadbalancer_test.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer falliti!" -ForegroundColor Red
}

# Esegui test sistema
Write-Host "`n🔧 Eseguendo test Sistema..." -ForegroundColor Cyan
go run ./test/test_system.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/s3.go ./src/rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Sistema completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Sistema falliti!" -ForegroundColor Red
}

# Esegui test load balancer ottimizzato
Write-Host "`n🚀 Eseguendo test Load Balancer Ottimizzato..." -ForegroundColor Cyan
go run ./test/test_optimized_loadbalancer.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer Ottimizzato completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer Ottimizzato falliti!" -ForegroundColor Red
}

# Esegui test load balancer semplice
Write-Host "`n⚡ Eseguendo test Load Balancer Semplice..." -ForegroundColor Cyan
go run ./test/test_loadbalancer.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer Semplice completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer Semplice falliti!" -ForegroundColor Red
}

# Torna alla directory originale
Set-Location $originalDir

Write-Host "`n🎉 Tutti i test Go completati!" -ForegroundColor Green
Write-Host "📁 Tornato alla directory: $(Get-Location)" -ForegroundColor Yellow
