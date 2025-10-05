#!/bin/bash

# Environment Management Script for MapReduce
# Supports both local development and AWS deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="local"
COMPOSE_FILE=""
ACTION=""

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] ACTION"
    echo ""
    echo "OPTIONS:"
    echo "  -e, --environment ENV    Environment: local, aws (default: local)"
    echo "  -f, --file FILE         Docker compose file (auto-detected if not specified)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "ACTIONS:"
    echo "  up                      Start services"
    echo "  down                    Stop services"
    echo "  restart                 Restart services"
    echo "  logs                    Show logs"
    echo "  status                  Show service status"
    echo "  build                   Build images"
    echo "  clean                   Clean up containers and images"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 up                           # Start local environment"
    echo "  $0 -e aws up                    # Start AWS environment"
    echo "  $0 -e local logs                # Show logs for local environment"
    echo "  $0 -f docker-compose.yml up     # Use specific compose file"
}

# Function to detect environment
detect_environment() {
    if [ -n "$DEPLOYMENT_ENV" ]; then
        ENVIRONMENT="$DEPLOYMENT_ENV"
    elif [ -n "$AWS_REGION" ]; then
        ENVIRONMENT="aws"
    else
        ENVIRONMENT="local"
    fi
}

# Function to set compose file based on environment
set_compose_file() {
    if [ -n "$COMPOSE_FILE" ]; then
        return
    fi
    
    case "$ENVIRONMENT" in
        "local")
            if [ -f "docker/docker-compose.local.yml" ]; then
                COMPOSE_FILE="docker/docker-compose.local.yml"
            elif [ -f "docker/docker-compose.yml" ]; then
                COMPOSE_FILE="docker/docker-compose.yml"
            else
                print_error "No local compose file found!"
                exit 1
            fi
            ;;
        "aws")
            if [ -f "aws/docker/docker-compose.master.yml" ]; then
                COMPOSE_FILE="aws/docker/docker-compose.master.yml"
            else
                print_error "No AWS compose file found!"
                exit 1
            fi
            ;;
        *)
            print_error "Unknown environment: $ENVIRONMENT"
            exit 1
            ;;
    esac
}

# Function to start services
start_services() {
    print_header "Starting MapReduce Services"
    print_status "Environment: $ENVIRONMENT"
    print_status "Compose file: $COMPOSE_FILE"
    
    # Set environment variables for local development
    if [ "$ENVIRONMENT" = "local" ]; then
        export DEPLOYMENT_ENV=local
        export LOCAL_MODE=true
        export RAFT_ADDRESSES="master0:1234,master1:1234,master2:1234"
        export RPC_ADDRESSES="master0:8000,master1:8001,master2:8002"
        export WORKER_ADDRESSES="worker1:8081,worker2:8081,worker3:8081"
    fi
    
    docker-compose -f "$COMPOSE_FILE" up -d
    
    print_status "Services started successfully!"
    print_status "Dashboard: http://localhost:8080"
    print_status "Health check: http://localhost:8080/health"
}

# Function to stop services
stop_services() {
    print_header "Stopping MapReduce Services"
    
    docker-compose -f "$COMPOSE_FILE" down
    
    print_status "Services stopped successfully!"
}

# Function to restart services
restart_services() {
    print_header "Restarting MapReduce Services"
    
    stop_services
    sleep 2
    start_services
}

# Function to show logs
show_logs() {
    print_header "MapReduce Service Logs"
    
    docker-compose -f "$COMPOSE_FILE" logs -f
}

# Function to show status
show_status() {
    print_header "MapReduce Service Status"
    
    docker-compose -f "$COMPOSE_FILE" ps
}

# Function to build images
build_images() {
    print_header "Building MapReduce Images"
    
    docker-compose -f "$COMPOSE_FILE" build
    
    print_status "Images built successfully!"
}

# Function to clean up
clean_up() {
    print_header "Cleaning Up MapReduce Environment"
    
    print_warning "This will remove all containers, images, and volumes!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker-compose -f "$COMPOSE_FILE" down -v --rmi all
        docker system prune -f
        print_status "Cleanup completed!"
    else
        print_status "Cleanup cancelled."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -f|--file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        up|down|restart|logs|status|build|clean)
            ACTION="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Check if action is specified
if [ -z "$ACTION" ]; then
    print_error "No action specified!"
    show_usage
    exit 1
fi

# Detect environment if not specified
detect_environment

# Set compose file
set_compose_file

# Execute action
case "$ACTION" in
    "up")
        start_services
        ;;
    "down")
        stop_services
        ;;
    "restart")
        restart_services
        ;;
    "logs")
        show_logs
        ;;
    "status")
        show_status
        ;;
    "build")
        build_images
        ;;
    "clean")
        clean_up
        ;;
    *)
        print_error "Unknown action: $ACTION"
        show_usage
        exit 1
        ;;
esac
