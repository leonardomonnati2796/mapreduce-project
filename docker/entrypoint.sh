#!/bin/bash

# Entrypoint script per MapReduce su AWS
set -e

# Log di avvio
echo "=== MapReduce AWS Entrypoint ==="
echo "Timestamp: $(date)"
echo "Service: ${SERVICE_TYPE:-unknown}"
echo "AWS Region: ${AWS_REGION:-not-set}"
echo "S3 Bucket: ${AWS_S3_BUCKET:-not-set}"

# Configura AWS CLI se le credenziali sono disponibili
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Configuring AWS CLI..."
    aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
    aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
    aws configure set default.region "${AWS_REGION:-us-east-1}"
    aws configure set default.output json
    
    # Test AWS connection
    if aws sts get-caller-identity > /dev/null 2>&1; then
        echo "AWS CLI configured successfully"
    else
        echo "Warning: AWS CLI configuration failed"
    fi
else
    echo "Warning: AWS credentials not provided"
fi

# Crea directory necessarie
mkdir -p /tmp/mapreduce /var/log/mapreduce

# Configura log rotation
if [ ! -f /etc/logrotate.d/mapreduce ]; then
    cat > /etc/logrotate.d/mapreduce << EOF
/var/log/mapreduce/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
fi

# Funzione per cleanup al termine
cleanup() {
    echo "Cleaning up..."
    # Sincronizza dati su S3 se configurato
    if [ "$S3_SYNC_ENABLED" = "true" ] && [ -n "$AWS_S3_BUCKET" ]; then
        echo "Syncing data to S3..."
        ./s3-sync --backup || echo "S3 sync failed"
    fi
    exit 0
}

# Registra signal handlers
trap cleanup SIGTERM SIGINT

# Determina il comando da eseguire
if [ $# -eq 0 ]; then
    # Nessun argomento, usa il comando di default
    exec ./mapreduce
else
    # Esegui il comando passato
    exec "$@"
fi
