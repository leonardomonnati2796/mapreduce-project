#!/bin/bash

# Script per aggiornare il progetto MapReduce su EC2
# Uso: ./update-project.sh

set -e

echo "Aggiornando il progetto MapReduce..."

# Vai nella directory del progetto
cd ~/mapreduce-project

# Pull delle ultime modifiche
echo "Scaricando le ultime modifiche da GitHub..."
git pull origin main

# Ferma i container esistenti
echo "Fermando i container esistenti..."
docker compose -f docker/docker-compose.yml down

# Riavvia con le nuove modifiche
echo "Riavviando i servizi con le nuove modifiche..."
docker compose -f docker/docker-compose.yml up -d --build

# Verifica che tutto funzioni
echo "Verificando lo stato dei servizi..."
sleep 10
docker compose -f docker/docker-compose.yml ps

# Test dell'endpoint
echo "Testando l'endpoint di health..."
curl -f http://localhost:8080/health && echo "Health check OK" || echo "Health check failed"

echo "Aggiornamento completato!"
echo "Dashboard: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || hostname -I | awk '{print $1}'):8080/dashboard"
