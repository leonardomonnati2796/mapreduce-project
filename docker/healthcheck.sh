#!/bin/bash

# Health check script per MapReduce su AWS
set -e

# Determina il tipo di servizio basato sulla variabile d'ambiente
SERVICE_TYPE=${SERVICE_TYPE:-"unknown"}

case $SERVICE_TYPE in
    "master")
        # Health check per master
        PORT=${METRICS_PORT:-9090}
        if curl -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
            echo "Master health check passed"
            exit 0
        else
            echo "Master health check failed"
            exit 1
        fi
        ;;
    "worker")
        # Health check per worker - verifica che sia in esecuzione
        if pgrep -f "mapreduce worker" > /dev/null; then
            echo "Worker health check passed"
            exit 0
        else
            echo "Worker health check failed"
            exit 1
        fi
        ;;
    "dashboard")
        # Health check per dashboard
        PORT=${DASHBOARD_PORT:-8080}
        if curl -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
            echo "Dashboard health check passed"
            exit 0
        else
            echo "Dashboard health check failed"
            exit 1
        fi
        ;;
    "nginx")
        # Health check per nginx
        if wget --quiet --tries=1 --spider "http://localhost/health" > /dev/null 2>&1; then
            echo "Nginx health check passed"
            exit 0
        else
            echo "Nginx health check failed"
            exit 1
        fi
        ;;
    *)
        # Health check generico
        echo "Generic health check - service running"
        exit 0
        ;;
esac
