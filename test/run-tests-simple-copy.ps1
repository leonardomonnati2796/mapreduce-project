# Script semplice per eseguire i test copiando i file necessari

Write-Host "Eseguendo test Load Balancer con copia file..." -ForegroundColor Green

# Crea una directory temporanea per i test
$testDir = "test-temp"
if (Test-Path $testDir) {
    Remove-Item $testDir -Recurse -Force
}
New-Item -ItemType Directory -Path $testDir | Out-Null

Write-Host "Directory temporanea creata: $testDir" -ForegroundColor Yellow

# Copia i file necessari
Write-Host "Copiando file necessari..." -ForegroundColor Yellow
Copy-Item "src/loadbalancer.go" -Destination "$testDir/" -Force
Copy-Item "src/health.go" -Destination "$testDir/" -Force
Copy-Item "src/config.go" -Destination "$testDir/" -Force
Copy-Item "src/rpc.go" -Destination "$testDir/" -Force
Copy-Item "src/s3.go" -Destination "$testDir/" -Force
Copy-Item "test/loadbalancer_test_integration_test.go" -Destination "$testDir/" -Force

Write-Host "File copiati con successo!" -ForegroundColor Green

# Esegui i test
Write-Host "Eseguendo test Load Balancer..." -ForegroundColor Cyan
Set-Location $testDir
go test -v loadbalancer_test_integration_test.go loadbalancer.go health.go config.go rpc.go

if ($LASTEXITCODE -eq 0) {
    Write-Host "Test Load Balancer completati con successo!" -ForegroundColor Green
} else {
    Write-Host "Test Load Balancer falliti!" -ForegroundColor Red
}

# Torna alla directory principale
Set-Location ..

# Pulisci la directory temporanea
Write-Host "Pulendo directory temporanea..." -ForegroundColor Yellow
Remove-Item $testDir -Recurse -Force

Write-Host "Directory temporanea rimossa!" -ForegroundColor Green
Write-Host "Test completati!" -ForegroundColor Green
