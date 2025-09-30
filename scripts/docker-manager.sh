#!/bin/bash
# Script bash per gestione Docker cluster MapReduce

ACTION=$1

case $ACTION in
    "start")
        echo "=== AVVIO CLUSTER MAPREDUCE ==="
        docker compose -f docker/docker-compose.yml up -d
        echo "Cluster avviato"
        ;;
    "stop")
        echo "=== FERMATA CLUSTER MAPREDUCE ==="
        docker compose -f docker/docker-compose.yml down
        echo "Cluster fermato"
        ;;
    "reset")
        echo "=== RESTART CLUSTER MAPREDUCE ==="
        docker compose -f docker/docker-compose.yml down
        sleep 2
        docker compose -f docker/docker-compose.yml up -d
        echo "Cluster riavviato"
        ;;
    "status")
        echo "=== STATO CLUSTER ==="
        docker ps --filter "name=docker-"
        ;;
    *)
        echo "Azione non riconosciuta: $ACTION"
        echo "Azioni disponibili: start, stop, reset, status"
        exit 1
        ;;
esac
