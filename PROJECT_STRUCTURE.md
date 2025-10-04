# 📁 MapReduce Project Structure

## Overview
Professional MapReduce implementation with advanced fault tolerance, load balancing, and cloud deployment capabilities.

## Directory Structure

```
mapreduce-project/
├── src/                           # Main source code
│   ├── main.go                    # Entry point
│   ├── master.go                  # Master node implementation with Raft consensus
│   ├── mapreduce.go               # Worker node implementation
│   ├── dashboard.go               # Web dashboard with WebSocket support
│   ├── loadbalancer.go            # Load balancer with 5 strategies
│   ├── health.go                  # Infrastructure health monitoring
│   ├── logger.go                  # Structured logging system
│   ├── constants.go               # Centralized constants
│   ├── config.go                  # Configuration management
│   ├── rpc.go                     # RPC types and utilities
│   ├── s3.go                      # S3 storage integration
│   ├── metrics.go                 # Prometheus metrics
│   └── unused_functions_analysis.md  # Function analysis documentation
│
├── web/                           # Web interface assets
│   ├── templates/                 # HTML templates
│   └── static/                    # CSS, JS, images
│       ├── css/
│       └── js/
│
├── test/                          # Test suite
│   ├── loadbalancer_test.go      # Load balancer tests
│   ├── advanced_fault_tolerance_test.go  # Fault tolerance tests
│   ├── test_system.go             # System integration tests
│   └── run-*.ps1/sh               # Test execution scripts
│
├── demos/                         # Demo files
│   ├── fault_tolerance_demo_simple.go
│   ├── health_demo_simple.go
│   └── s3-demo.go
│
├── aws/                           # AWS deployment
│   ├── config/                    # Configuration files
│   ├── terraform/                 # Infrastructure as Code
│   ├── scripts/                   # Deployment scripts
│   ├── backup/                    # Backup configurations
│   └── monitoring/                # CloudWatch and alerts
│
├── docker/                        # Docker deployment
│   ├── docker-compose.yml         # Local development
│   ├── docker-compose.aws.yml     # AWS deployment
│   ├── Dockerfile                 # Container image
│   └── entrypoint.sh              # Container startup script
│
├── scripts/                       # Utility scripts
│   ├── configure-s3-aws.*         # S3 configuration
│   ├── deploy-*.sh/ps1            # Deployment automation
│   └── open-dashboard.*           # Dashboard launcher
│
├── data/                          # Input/output data
│   ├── Words*.txt                 # Input files
│   └── output/                    # MapReduce results
│
├── report/                        # Project documentation
│   ├── report.tex                 # LaTeX report
│   ├── report.pdf                 # Compiled report
│   └── diagrams/                  # Architecture diagrams
│
└── docs/                          # Documentation files
    ├── README.md                  # Main documentation
    ├── AWS_*.md                   # AWS guides
    ├── TEST_*.md                  # Testing guides
    ├── FAULT_TOLERANCE_*.md       # Fault tolerance documentation
    └── LOADBALANCER_S3_GUIDE.md   # Integration guide

```

## Core Components

### 🎯 Master Node (`master.go`)
- Raft consensus for leader election
- Task distribution and monitoring
- Worker health tracking
- Fault recovery mechanisms
- S3 backup integration

### 👷 Worker Nodes (`mapreduce.go`)
- Map and Reduce task execution
- Automatic reconnection
- Checkpointing for fault tolerance
- Load balancing integration

### ⚖️ Load Balancer (`loadbalancer.go`)
- 5 balancing strategies:
  - Round Robin
  - Weighted Round Robin
  - Least Connections
  - Random
  - Health-Based
- Unified health checking
- Advanced fault tolerance
- Real-time statistics

### 🏥 Health Monitoring (`health.go`)
- Infrastructure-level checks
- Disk space monitoring
- Network connectivity
- S3 connection status
- Raft cluster health
- Docker environment checks

### 📊 Dashboard (`dashboard.go`)
- Real-time WebSocket updates
- Job submission and monitoring
- Worker status visualization
- Metrics and statistics
- Interactive UI

### 📝 Logging System (`logger.go`)
- Structured logging (DEBUG, INFO, WARN, ERROR)
- File and console output
- Timestamp and context tracking
- Color-coded messages

## Key Features

✅ **Fault Tolerance**
- Mapper failure recovery
- Reducer failure recovery with checkpointing
- Task verification and retry logic
- Data integrity checks

✅ **Load Balancing**
- Multiple strategies
- Health-based routing
- Automatic failover
- Statistics tracking

✅ **Cloud Deployment**
- AWS EC2 ready
- Docker containerization
- S3 storage integration
- Terraform IaC

✅ **Monitoring**
- Prometheus metrics
- Health endpoints
- Real-time dashboard
- Comprehensive logging

## Running the Project

### Local Development
```bash
# Start master
go run src/*.go master 0 data/Words.txt,data/Words2.txt 3

# Start worker
go run src/*.go worker worker-1

# Start dashboard
go run src/*.go dashboard
```

### Docker Deployment
```bash
# Local
docker-compose up

# AWS
docker-compose -f docker/docker-compose.aws.yml up
```

### AWS Deployment
```bash
# Configure AWS
./scripts/configure-s3-aws.sh

# Deploy with Terraform
cd aws/terraform
terraform apply
```

## Testing

```bash
# Run all tests
cd test
go test -v ./...

# Run load balancer tests
go test -v -run TestLoadBalancer

# Run fault tolerance tests
go test -v -run TestFaultTolerance
```

## Configuration

### Environment Variables
- `MAPREDUCE_CONFIG`: Config file path
- `LOG_FILE`: Log output file
- `LOG_LEVEL`: DEBUG, INFO, WARN, ERROR
- `S3_SYNC_ENABLED`: Enable S3 sync
- `S3_BUCKET`: S3 bucket name
- `S3_REGION`: AWS region

### Config File (`config.json`)
```json
{
  "dashboard_port": 8080,
  "raft_addresses": ["localhost:1234", "localhost:1235", "localhost:1236"],
  "rpc_addresses": ["localhost:8000", "localhost:8001", "localhost:8002"],
  "temp_path": "temp-local",
  "output_path": "output",
  "raft_data_path": "raft-data"
}
```

## Architecture

### Raft Consensus
- Leader election
- Log replication
- State machine consistency
- Fault tolerance

### MapReduce Flow
1. **Input Split**: Files divided into chunks
2. **Map Phase**: Parallel processing by workers
3. **Intermediate Storage**: Partitioned output
4. **Reduce Phase**: Aggregation by reducers
5. **Final Output**: Merged results

### Fault Tolerance Flow
1. **Failure Detection**: Health monitoring
2. **State Recovery**: Checkpoints and logs
3. **Task Reassignment**: Load balancer
4. **Verification**: Data integrity checks

## Maintenance

### Adding New Features
1. Update `src/` with new code
2. Add tests in `test/`
3. Update documentation in `docs/`
4. Run full test suite
5. Update `PROJECT_STRUCTURE.md`

### Troubleshooting
- Check logs in `LOG_FILE`
- Verify health endpoint: `http://localhost:8080/health`
- Monitor Raft cluster status
- Check S3 connectivity

## License
See LICENSE file for details.

## Contributors
See CONTRIBUTORS file for details.

## Version
Current Version: 2.0.0 (October 2025)
- Complete logging system
- Advanced fault tolerance
- Load balancer implementation
- AWS deployment ready

