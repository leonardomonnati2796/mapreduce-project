# Script per eseguire i test del load balancer dalla directory principale
# Questo script deve essere eseguito dalla directory principale del progetto

Write-Host "🧪 Eseguendo test Load Balancer dalla directory principale..." -ForegroundColor Green

# Esegui i test load balancer dalla directory principale
Write-Host "📊 Eseguendo test Load Balancer..." -ForegroundColor Cyan
go test -v -tags=integration ./test/loadbalancer_test_integration.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Test Load Balancer completati con successo!" -ForegroundColor Green
} else {
    Write-Host "❌ Test Load Balancer falliti!" -ForegroundColor Red
}

Write-Host "🎉 Test completati!" -ForegroundColor Green
