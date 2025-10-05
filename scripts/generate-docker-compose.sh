#!/bin/bash

# Script to generate dynamic docker-compose files based on environment variables
# Usage: ./scripts/generate-docker-compose.sh [local|aws]

set -e

# Default values
ENVIRONMENT=${1:-local}
OUTPUT_DIR="docker"
TEMPLATE_DIR="docker/templates"

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading environment variables from .env file..."
    export $(cat .env | grep -v '^#' | xargs)
fi

# Set default values if not provided
export RAFT_PORT=${RAFT_PORT:-1234}
export RPC_PORT=${RPC_PORT:-8000}
export WORKER_PORT=${WORKER_PORT:-8081}
export DASHBOARD_PORT=${DASHBOARD_PORT:-8080}
export HEALTH_PORT=${HEALTH_PORT:-8100}
export NGINX_PORT=${NGINX_PORT:-80}
export REDIS_PORT=${REDIS_PORT:-6379}

# Multi-instance port configuration
export RAFT_PORT_0=${RAFT_PORT_0:-1234}
export RAFT_PORT_1=${RAFT_PORT_1:-1235}
export RAFT_PORT_2=${RAFT_PORT_2:-1236}
export RPC_PORT_0=${RPC_PORT_0:-8000}
export RPC_PORT_1=${RPC_PORT_1:-8001}
export RPC_PORT_2=${RPC_PORT_2:-8002}
export HEALTH_PORT_0=${HEALTH_PORT_0:-8100}
export HEALTH_PORT_1=${HEALTH_PORT_1:-8101}
export HEALTH_PORT_2=${HEALTH_PORT_2:-8102}
export WORKER_PORT_1=${WORKER_PORT_1:-8081}
export WORKER_PORT_2=${WORKER_PORT_2:-8082}
export WORKER_PORT_3=${WORKER_PORT_3:-8083}

# Network configuration
export DEPLOYMENT_ENV=${DEPLOYMENT_ENV:-local}
export LOCAL_MODE=${LOCAL_MODE:-true}

if [ "$ENVIRONMENT" = "local" ]; then
    export RAFT_ADDRESSES=${RAFT_ADDRESSES:-"master0:1234,master1:1235,master2:1236"}
    export RPC_ADDRESSES=${RPC_ADDRESSES:-"master0:8000,master1:8001,master2:8002"}
    export WORKER_ADDRESSES=${WORKER_ADDRESSES:-"worker1:8081,worker2:8082,worker3:8083"}
    export MY_PRIVATE_IP=${MY_PRIVATE_IP:-localhost}
    export MASTER_IPS=${MASTER_IPS:-"master0,master1,master2"}
    export WORKER_IPS=${WORKER_IPS:-"worker1,worker2,worker3"}
else
    # For AWS, these will be set by user_data.sh
    export RAFT_ADDRESSES=${RAFT_ADDRESSES:-""}
    export RPC_ADDRESSES=${RPC_ADDRESSES:-""}
    export WORKER_ADDRESSES=${WORKER_ADDRESSES:-""}
    export MY_PRIVATE_IP=${MY_PRIVATE_IP:-""}
    export MASTER_IPS=${MASTER_IPS:-""}
    export WORKER_IPS=${WORKER_IPS:-""}
fi

echo "Generating docker-compose for environment: $ENVIRONMENT"
echo "Using ports:"
echo "  RAFT: $RAFT_PORT_0, $RAFT_PORT_1, $RAFT_PORT_2"
echo "  RPC: $RPC_PORT_0, $RPC_PORT_1, $RPC_PORT_2"
echo "  Worker: $WORKER_PORT_1, $WORKER_PORT_2, $WORKER_PORT_3"
echo "  Dashboard: $DASHBOARD_PORT"
echo "  Health: $HEALTH_PORT_0, $HEALTH_PORT_1, $HEALTH_PORT_2"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate docker-compose.local.yml
cat > "$OUTPUT_DIR/docker-compose.local.yml" << EOF
version: '3.8'

services:
  # Master 0
  master0:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-master-0
    ports:
      - "$RAFT_PORT_0:$RAFT_PORT_0"
      - "$RPC_PORT_0:$RPC_PORT_0"
      - "$HEALTH_PORT_0:$HEALTH_PORT_0"
    environment:
      - NODE_ROLE=master
      - MASTER_ID=0
      - RAFT_PORT=$RAFT_PORT_0
      - RPC_PORT=$RPC_PORT_0
      - HEALTH_PORT=$HEALTH_PORT_0
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$HEALTH_PORT_0/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Master 1
  master1:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-master-1
    ports:
      - "$RAFT_PORT_1:$RAFT_PORT_1"
      - "$RPC_PORT_1:$RPC_PORT_1"
      - "$HEALTH_PORT_1:$HEALTH_PORT_1"
    environment:
      - NODE_ROLE=master
      - MASTER_ID=1
      - RAFT_PORT=$RAFT_PORT_1
      - RPC_PORT=$RPC_PORT_1
      - HEALTH_PORT=$HEALTH_PORT_1
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$HEALTH_PORT_1/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Master 2
  master2:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-master-2
    ports:
      - "$RAFT_PORT_2:$RAFT_PORT_2"
      - "$RPC_PORT_2:$RPC_PORT_2"
      - "$HEALTH_PORT_2:$HEALTH_PORT_2"
    environment:
      - NODE_ROLE=master
      - MASTER_ID=2
      - RAFT_PORT=$RAFT_PORT_2
      - RPC_PORT=$RPC_PORT_2
      - HEALTH_PORT=$HEALTH_PORT_2
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$HEALTH_PORT_2/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Worker 1
  worker1:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-worker-1
    ports:
      - "$WORKER_PORT_1:$WORKER_PORT_1"
    environment:
      - NODE_ROLE=worker
      - WORKER_ID=1
      - WORKER_PORT=$WORKER_PORT_1
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    depends_on:
      - master0
      - master1
      - master2

  # Worker 2
  worker2:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-worker-2
    ports:
      - "$WORKER_PORT_2:$WORKER_PORT_2"
    environment:
      - NODE_ROLE=worker
      - WORKER_ID=2
      - WORKER_PORT=$WORKER_PORT_2
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    depends_on:
      - master0
      - master1
      - master2

  # Worker 3
  worker3:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-worker-3
    ports:
      - "$WORKER_PORT_3:$WORKER_PORT_3"
    environment:
      - NODE_ROLE=worker
      - WORKER_ID=3
      - WORKER_PORT=$WORKER_PORT_3
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    depends_on:
      - master0
      - master1
      - master2

  # Dashboard
  dashboard:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: mapreduce-dashboard
    command: ["./mapreduce", "dashboard", "--port", "$DASHBOARD_PORT"]
    ports:
      - "$DASHBOARD_PORT:$DASHBOARD_PORT"
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    environment:
      - DASHBOARD_PORT=$DASHBOARD_PORT
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=$DEPLOYMENT_ENV
      - LOCAL_MODE=$LOCAL_MODE
      - TMP_PATH=/tmp/mapreduce
    networks:
      - mapreduce-net
    depends_on:
      - master0
      - master1
      - master2

  # Nginx Load Balancer
  nginx:
    image: nginx:alpine
    container_name: mapreduce-nginx
    ports:
      - "$NGINX_PORT:$NGINX_PORT"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    environment:
      - NGINX_PORT=$NGINX_PORT
      - DASHBOARD_PORT=$DASHBOARD_PORT
      - RPC_PORT_0=$RPC_PORT_0
      - RPC_PORT_1=$RPC_PORT_1
      - RPC_PORT_2=$RPC_PORT_2
      - WORKER_PORT_1=$WORKER_PORT_1
      - WORKER_PORT_2=$WORKER_PORT_2
      - WORKER_PORT_3=$WORKER_PORT_3
    networks:
      - mapreduce-net
    depends_on:
      - master0
      - master1
      - master2
      - worker1
      - worker2
      - worker3
      - dashboard

  # Redis for caching
  redis:
    image: redis:alpine
    container_name: mapreduce-redis
    ports:
      - "$REDIS_PORT:$REDIS_PORT"
    environment:
      - REDIS_PORT=$REDIS_PORT
    networks:
      - mapreduce-net
    volumes:
      - redis-data:/data

volumes:
  intermediate-data:
  redis-data:

networks:
  mapreduce-net:
    driver: bridge
EOF

echo "Generated docker-compose.local.yml with dynamic port configuration"

# Generate docker-compose.aws.yml for AWS deployment
cat > "$OUTPUT_DIR/docker-compose.aws.yml" << EOF
version: '3.8'

services:
  # Master (AWS)
  master:
    build:
      context: ..
      dockerfile: docker/Dockerfile.aws
    container_name: mapreduce-master
    ports:
      - "$RAFT_PORT:$RAFT_PORT"
      - "$RPC_PORT:$RPC_PORT"
      - "$HEALTH_PORT:$HEALTH_PORT"
    environment:
      - NODE_ROLE=master
      - RAFT_PORT=$RAFT_PORT
      - RPC_PORT=$RPC_PORT
      - HEALTH_PORT=$HEALTH_PORT
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=aws
      - LOCAL_MODE=false
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$HEALTH_PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # Worker (AWS)
  worker:
    build:
      context: ..
      dockerfile: docker/Dockerfile.aws
    container_name: mapreduce-worker
    ports:
      - "$WORKER_PORT:$WORKER_PORT"
    environment:
      - NODE_ROLE=worker
      - WORKER_PORT=$WORKER_PORT
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=aws
      - LOCAL_MODE=false
      - TMP_PATH=/tmp/mapreduce
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    networks:
      - mapreduce-net
    depends_on:
      - master

  # Dashboard (AWS)
  dashboard:
    build:
      context: ..
      dockerfile: docker/Dockerfile.aws
    container_name: mapreduce-dashboard
    command: ["./mapreduce", "dashboard", "--port", "$DASHBOARD_PORT"]
    ports:
      - "$DASHBOARD_PORT:$DASHBOARD_PORT"
    volumes:
      - intermediate-data:/tmp/mapreduce
      - ../data:/root/data:ro
    environment:
      - DASHBOARD_PORT=$DASHBOARD_PORT
      - RAFT_ADDRESSES=$RAFT_ADDRESSES
      - RPC_ADDRESSES=$RPC_ADDRESSES
      - WORKER_ADDRESSES=$WORKER_ADDRESSES
      - MY_PRIVATE_IP=$MY_PRIVATE_IP
      - MASTER_IPS=$MASTER_IPS
      - WORKER_IPS=$WORKER_IPS
      - DEPLOYMENT_ENV=aws
      - LOCAL_MODE=false
      - TMP_PATH=/tmp/mapreduce
    networks:
      - mapreduce-net
    depends_on:
      - master

volumes:
  intermediate-data:

networks:
  mapreduce-net:
    driver: bridge
EOF

echo "Generated docker-compose.aws.yml with dynamic port configuration"

echo "✅ Docker Compose files generated successfully!"
echo "📁 Files created:"
echo "   - docker/docker-compose.local.yml"
echo "   - docker/docker-compose.aws.yml"
echo ""
echo "🚀 To use the generated files:"
echo "   Local: docker-compose -f docker/docker-compose.local.yml up"
echo "   AWS:   docker-compose -f docker/docker-compose.aws.yml up"
