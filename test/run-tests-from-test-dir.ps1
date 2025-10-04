# Script per eseguire i test dalla cartella test
# Questo script copia i file necessari nella directory test e esegue i test

Write-Host "🧪 Eseguendo test dalla cartella test..." -ForegroundColor Green

# Copia i file necessari nella directory test
Write-Host "📁 Copiando file necessari..." -ForegroundColor Yellow
Copy-Item "../src/loadbalancer.go" -Destination "." -Force
Copy-Item "../src/health.go" -Destination "." -Force
Copy-Item "../src/config.go" -Destination "." -Force
Copy-Item "../src/rpc.go" -Destination "." -Force
Copy-Item "../src/s3.go" -Destination "." -Force

Write-Host "✅ File copiati con successo!" -ForegroundColor Green

# Esegui i test load balancer
Write-Host "`n📊 Eseguendo test Load Balancer..." -ForegroundColor Cyan
go test -v loadbalancer_test.go loadbalancer.go health.go config.go rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer falliti!" -ForegroundColor Red
}

# Esegui test sistema
Write-Host "`n🔧 Eseguendo test Sistema..." -ForegroundColor Cyan
go run test_system.go loadbalancer.go health.go config.go s3.go rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Sistema completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Sistema falliti!" -ForegroundColor Red
}

# Esegui test load balancer ottimizzato
Write-Host "`n🚀 Eseguendo test Load Balancer Ottimizzato..." -ForegroundColor Cyan
go run test_optimized_loadbalancer.go loadbalancer.go health.go config.go rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer Ottimizzato completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer Ottimizzato falliti!" -ForegroundColor Red
}

# Esegui test load balancer semplice
Write-Host "`n⚡ Eseguendo test Load Balancer Semplice..." -ForegroundColor Cyan
go run test_loadbalancer.go loadbalancer.go health.go config.go rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer Semplice completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer Semplice falliti!" -ForegroundColor Red
}

# Pulisci i file copiati
Write-Host "`n🧹 Pulendo file temporanei..." -ForegroundColor Yellow
Remove-Item "loadbalancer.go" -Force -ErrorAction SilentlyContinue
Remove-Item "health.go" -Force -ErrorAction SilentlyContinue
Remove-Item "config.go" -Force -ErrorAction SilentlyContinue
Remove-Item "rpc.go" -Force -ErrorAction SilentlyContinue
Remove-Item "s3.go" -Force -ErrorAction SilentlyContinue

Write-Host "✅ File temporanei rimossi!" -ForegroundColor Green
Write-Host "Tutti i test completati dalla cartella test!" -ForegroundColor Green
