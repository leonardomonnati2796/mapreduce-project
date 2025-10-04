#!/bin/bash

# Script per eseguire i test Go dalla cartella test
# Questo script deve essere eseguito dalla directory principale del progetto

echo "🧪 Eseguendo test Go dalla cartella test..."

# Cambia alla directory principale
ORIGINAL_DIR=$(pwd)
cd ..

echo "📁 Directory corrente: $(pwd)"

# Esegui i test load balancer
echo ""
echo "📊 Eseguendo test Load Balancer..."
go test -v ./test/loadbalancer_test.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if [ $? -eq 0 ]; then
    echo "✅ Test Load Balancer completati con successo!"
else
    echo "❌ Test Load Balancer falliti!"
fi

# Esegui test sistema
echo ""
echo "🔧 Eseguendo test Sistema..."
go run ./test/test_system.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/s3.go ./src/rpc.go

if [ $? -eq 0 ]; then
    echo "✅ Test Sistema completati con successo!"
else
    echo "❌ Test Sistema falliti!"
fi

# Esegui test load balancer ottimizzato
echo ""
echo "🚀 Eseguendo test Load Balancer Ottimizzato..."
go run ./test/test_optimized_loadbalancer.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if [ $? -eq 0 ]; then
    echo "✅ Test Load Balancer Ottimizzato completati con successo!"
else
    echo "❌ Test Load Balancer Ottimizzato falliti!"
fi

# Esegui test load balancer semplice
echo ""
echo "⚡ Eseguendo test Load Balancer Semplice..."
go run ./test/test_loadbalancer.go ./src/loadbalancer.go ./src/health.go ./src/config.go ./src/rpc.go

if [ $? -eq 0 ]; then
    echo "✅ Test Load Balancer Semplice completati con successo!"
else
    echo "❌ Test Load Balancer Semplice falliti!"
fi

# Torna alla directory originale
cd "$ORIGINAL_DIR"

echo ""
echo "🎉 Tutti i test Go completati!"
echo "📁 Tornato alla directory: $(pwd)"
